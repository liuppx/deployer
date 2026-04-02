#!/usr/bin/env bash
# check module code status, build package if needed, then upload with retry

set -euo pipefail
shopt -s nullglob

script_dir=$(cd "$(dirname "$0")" || exit 1; pwd)
# shellcheck disable=SC1091
source "${script_dir}/common.sh"

# Use a deterministic PATH for non-login shells (cron/systemd).
export PATH="/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

init_log_file "check-code-status.log"

config_file="${script_dir}/modules.conf"
code_root="/root/code"
package_root="/opt/package"
transfer_script="${script_dir}/transfer_packages.sh"
dingtalk_script="${script_dir}/../dingtalk-notify/dingtalk_reminder.py"
dingtalk_scene="create_package"
# True: read *_RECEIVER from .env and @userIds; False: no @
dingtalk_need_at="${DINGTALK_NEED_AT:-False}"
overall_status=0

ensure_go_in_path() {
    if command -v go >/dev/null 2>&1; then
        return 0
    fi

    if [[ -x /usr/local/go/bin/go ]]; then
        export PATH="${PATH}:/usr/local/go/bin"
    fi
    if command -v go >/dev/null 2>&1; then
        return 0
    fi

    # Non-login shells (cron/systemd) often miss /etc/profile PATH exports.
    if [[ -f /etc/profile ]]; then
        # shellcheck disable=SC1091
        source /etc/profile >/dev/null 2>&1 || true
    fi
    command -v go >/dev/null 2>&1
}

usage() {
    log "Usage: $0"
    log "Read modules from ${config_file}, then check/build/upload packages."
}

upload_with_retry() {
    local filename=$1
    local attempt

    for attempt in 1 2 3; do
        log "upload attempt ${attempt}/3: ${filename}"
        if bash "$transfer_script" upload "$filename" >> "$LOGFILE" 2>&1; then
            log "upload completed: ${filename}"
            notify_dingtalk "$dingtalk_need_at" "From vm200: upload completed: ${filename}"
            return 0
        fi
        log "upload failed on attempt ${attempt}/3: ${filename}"
        sleep 2
    done

    return 1
}

notify_dingtalk() {
    local need_at=$1
    local message=$2

    if [[ ! -f "$dingtalk_script" ]]; then
        log "WARN! dingtalk script is missing: ${dingtalk_script}"
        return 0
    fi

    if ! python3 "$dingtalk_script" "$dingtalk_scene" "$need_at" "$message" >> "$LOGFILE" 2>&1; then
        log "WARN! failed to send dingtalk notification"
    fi
}

if [[ $# -ne 0 ]]; then
    usage
    exit 1
fi

load_modules "$config_file" || {
    usage
    exit 1
}

sync_main_latest() {
    local module_name=$1
    local module_dir=$2

    if ! git -C "$module_dir" fetch origin main >> "$LOGFILE" 2>&1; then
        log "ERROR! git fetch origin main failed for ${module_name}"
        return 1
    fi

    # Keep local workspace on main and fast-forward to origin/main.
    if git -C "$module_dir" show-ref --verify --quiet refs/heads/main; then
        if ! git -C "$module_dir" checkout main >> "$LOGFILE" 2>&1; then
            log "ERROR! git checkout main failed for ${module_name}"
            return 1
        fi
    else
        if ! git -C "$module_dir" checkout -b main --track origin/main >> "$LOGFILE" 2>&1; then
            log "ERROR! create local main from origin/main failed for ${module_name}"
            return 1
        fi
    fi

    if ! git -C "$module_dir" pull --ff-only origin main >> "$LOGFILE" 2>&1; then
        log "ERROR! git pull --ff-only origin main failed for ${module_name}"
        return 1
    fi

    return 0
}

select_latest_local_package() {
    local module_name=$1
    shift
    local candidates=("$@")
    local item name stem rest version commit
    local max_key="" max_name="" max_version="" max_commit="" max_stem=""
    local version_key=""

    for item in "${candidates[@]}"; do
        name=$(basename "$item")
        stem=${name%.tar.gz}

        if [[ "$stem" != "${module_name}-v"* ]]; then
            continue
        fi

        rest=${stem#"${module_name}-v"}
        commit=${rest##*-}
        version=${rest%-*}

        # Use fixed-length short commit to parse from right side.
        if [[ "${#commit}" -ne 7 || ! "$commit" =~ ^[0-9A-Za-z]{7}$ ]]; then
            continue
        fi
        if [[ "$version" == "$rest" || ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            continue
        fi

        version_key=$(version_key_from_version "$version") || continue
        if [[ -z "$max_name" || "$version_key" > "$max_key" || ( "$version_key" == "$max_key" && "$stem" > "$max_stem" ) ]]; then
            max_key="$version_key"
            max_name="$name"
            max_version="$version"
            max_commit="$commit"
            max_stem="$stem"
        fi
    done

    SELECTED_NAME="$max_name"
    SELECTED_VERSION="$max_version"
    SELECTED_COMMIT="$max_commit"
    SELECTED_VERSION_KEY="$max_key"
    [[ -n "$SELECTED_NAME" ]]
}

capture_output_package_state() {
    local module_name=$1
    local module_dir=$2
    local state_file=$3
    local package_path package_name package_hash

    : > "$state_file"
    for package_path in "${module_dir}/output/${module_name}-"*.tar.gz; do
        [[ -f "$package_path" ]] || continue
        package_name=$(basename "$package_path")
        package_hash=$(sha256sum "$package_path" | awk '{print $1}')
        printf '%s %s\n' "$package_name" "$package_hash" >> "$state_file"
    done
}

if [[ ! -f "$transfer_script" ]]; then
    log "ERROR! transfer script is missing: ${transfer_script}"
    exit 1
fi

mkdir -p "$package_root"

log "\nbegin check code status [$(date)]"
log "runtime PATH: ${PATH}"
if ensure_go_in_path; then
    log "go command detected: $(command -v go)"
else
    log "WARN! go command not found in PATH before module checks"
fi

for module_name in "${MODULES[@]}"; do
    log "\nhandle module [${module_name}]"

    module_dir="${code_root}/${module_name}"
    package_script="${module_dir}/scripts/package.sh"

    if [[ ! -d "$module_dir" ]]; then
        log "ERROR! code directory is missing: ${module_dir}"
        overall_status=1
        continue
    fi

    if [[ ! -d "${module_dir}/.git" ]]; then
        log "ERROR! not a git repository: ${module_dir}"
        overall_status=1
        continue
    fi

    if ! sync_main_latest "$module_name" "$module_dir"; then
        overall_status=1
        continue
    fi

    latest_commit=$(git -C "$module_dir" rev-parse --short=7 HEAD)
    need_build=0
    build_reason=""

    local_packages=("${package_root}/${module_name}-"*.tar.gz)
    if [[ ${#local_packages[@]} -eq 0 ]]; then
        need_build=1
        build_reason="no local package found in ${package_root}"
    else
        local_package_names=()
        for package_path in "${local_packages[@]}"; do
            local_package_names+=("$(basename "$package_path")")
        done

        if select_latest_local_package "$module_name" "${local_package_names[@]}"; then
            log "latest local package: ${SELECTED_NAME}"
            log "latest local package version: ${SELECTED_VERSION}, commit: ${SELECTED_COMMIT}"
            log "latest code commit: ${latest_commit}"

            if [[ "$SELECTED_COMMIT" != "$latest_commit" ]]; then
                need_build=1
                build_reason="latest code commit differs from latest package commit"
            else
                log "no build needed for ${module_name}, package commit matches latest code commit"
            fi
        else
            need_build=1
            build_reason="local package names are invalid"
        fi
    fi

    if [[ "$need_build" -eq 0 ]]; then
        continue
    fi

    if [[ ! -f "$package_script" ]]; then
        log "ERROR! package script is missing: ${package_script}"
        overall_status=1
        continue
    fi

    build_state_before=$(mktemp)
    capture_output_package_state "$module_name" "$module_dir" "$build_state_before"

    log "build package for ${module_name}: ${build_reason}"
    if ! (cd "$module_dir" && bash scripts/package.sh >> "$LOGFILE" 2>&1); then
        log "ERROR! package script failed for ${module_name}"
        rm -f "$build_state_before"
        overall_status=1
        continue
    fi

    output_packages=("${module_dir}/output/${module_name}-"*.tar.gz)
    if [[ ${#output_packages[@]} -eq 0 ]]; then
        log "ERROR! package file not found: ${module_dir}/output/${module_name}-*.tar.gz"
        rm -f "$build_state_before"
        overall_status=1
        continue
    fi

    output_package_names=()
    for package_path in "${output_packages[@]}"; do
        output_package_names+=("$(basename "$package_path")")
    done

    if ! select_latest_local_package "$module_name" "${output_package_names[@]}"; then
        log "ERROR! failed to find valid output package for ${module_name}"
        rm -f "$build_state_before"
        overall_status=1
        continue
    fi

    package_filename="$SELECTED_NAME"
    package_file="${module_dir}/output/${package_filename}"
    if [[ ! -f "$package_file" ]]; then
        log "ERROR! built package is missing: ${package_file}"
        rm -f "$build_state_before"
        overall_status=1
        continue
    fi

    if [[ "$SELECTED_COMMIT" != "$latest_commit" ]]; then
        log "ERROR! built package commit (${SELECTED_COMMIT}) does not match latest code commit (${latest_commit})"
        rm -f "$build_state_before"
        overall_status=1
        continue
    fi

    package_hash_after=$(sha256sum "$package_file" | awk '{print $1}')
    package_hash_before=$(awk -v target="$package_filename" '$1 == target {print $2; exit}' "$build_state_before")
    rm -f "$build_state_before"
    if [[ -n "$package_hash_before" && "$package_hash_before" == "$package_hash_after" ]]; then
        log "ERROR! no new package generated for ${module_name}: ${package_filename} unchanged after package.sh"
        overall_status=1
        continue
    fi

    cp -f "$package_file" "${package_root}/${package_filename}"
    log "package copied to ${package_root}/${package_filename}"

    if ! upload_with_retry "$package_filename"; then
        log "ERROR! upload still failed after 3 retries: ${package_filename}"
        notify_dingtalk "True" "From vm200: upload ${package_filename} failed"
        overall_status=1
        continue
    fi
done

log "\ncheck code status done. [$(date)]"
exit "$overall_status"
