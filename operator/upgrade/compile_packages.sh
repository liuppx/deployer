#!/usr/bin/env bash
# check module code status, build package if needed, then upload with retry

set -euo pipefail
shopt -s nullglob

script_dir=$(cd "$(dirname "$0")" || exit 1; pwd)
# shellcheck disable=SC1091
source "${script_dir}/common.sh"
feishu_common_sh="${script_dir}/../feishu-notify/common.sh"
if [[ -f "$feishu_common_sh" ]]; then
    # shellcheck disable=SC1090
    source "$feishu_common_sh"
fi

# Use a deterministic PATH for non-login shells (cron/systemd).
export PATH="/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

init_log_file "check-code-status.log"

config_file="${script_dir}/modules.conf"
env_file="${script_dir}/.env"
code_root="/root/code"
package_root="/opt/package"
transfer_script="${script_dir}/transfer_packages.sh"
release_notes_script="${script_dir}/../change-log/release_notes.sh"
dingtalk_script="${script_dir}/../dingtalk-notify/dingtalk_reminder.py"
dingtalk_scene="create_package"
feishu_scene="create_package"
overall_status=0
notify_type="版本生成"

if [[ -f "$env_file" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "$env_file"
    set +a
fi

# True: read *_RECEIVER from .env and @userIds; False: no @
dingtalk_need_at="${DINGTALK_NEED_AT:-False}"
notify_from="${NOTIFY_FROM:-}"
notify_dingtalk_enabled="${NOTIFY_DINGDING:-False}"
notify_feishu_enabled="${NOTIFY_FEISHU:-False}"

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

if [[ -z "${notify_from}" ]]; then
    notify_from=$(hostname)
fi

notify_owner="${notify_from}"

notify_now() {
    date '+%Y-%m-%d %H:%M'
}

format_release_notice() {
    local title=$1
    local version=$2
    local scope=$3
    local content=$4
    local status=$5

    cat <<EOF
【构建完成】${title} ${version}

时间：$(notify_now)
环境：${scope}
内容：${content}
状态：${status}
跟进人：
EOF
}

format_error_notice() {
    local title=$1
    local level=$2
    local status=$3
    local symptom=$4
    local impact=$5
    local action=$6
    local next_step=$7

    cat <<EOF
【系统异常】${title}

发现时间：$(notify_now)
异常等级：${level}
当前状态：${status}

异常现象：
- ${symptom}

影响范围：
- 影响用户：内部发布流程
- 影响功能：${impact}
- 影响环境：制品生成/上传

当前判断：
- ${action}

下一步动作：
1. ${next_step}
2. 检查日志 ${LOGFILE}

负责人：${notify_owner}
EOF
}

upload_with_retry() {
    local filename=$1
    local attempt
    local module_name="" version=""

    module_name=${filename%%-v*}
    if [[ -z "$module_name" || "$module_name" == "$filename" ]]; then
        module_name="构建产物"
    fi
    if artifact_info_from_name "$module_name" "$filename"; then
        version="v${PACKAGE_VERSION}"
    else
        version="$filename"
    fi

    for attempt in 1 2 3; do
        log "upload attempt ${attempt}/3: ${filename}"
        if bash "$transfer_script" upload "$filename" >> "$LOGFILE" 2>&1; then
            log "upload completed: ${filename}"
            notify_message "$dingtalk_need_at" "$(format_release_notice \
                "${module_name}/构建产物" \
                "${version}" \
                "编译节点" \
                "已完成产物上传：${filename}" \
                "已构建，上传完毕")"
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

notify_feishu() {
    local message=$1

    if ! declare -F send_feishu_message >/dev/null 2>&1; then
        return 0
    fi

    if ! send_feishu_message "$feishu_scene" "$message" >> "$LOGFILE" 2>&1; then
        log "WARN! failed to send feishu notification"
    fi
}

notify_message() {
    local need_at=$1
    local message=$2

    case "${notify_dingtalk_enabled}" in
        True|true)
            notify_dingtalk "$need_at" "$message"
            ;;
    esac

    case "${notify_feishu_enabled}" in
        True|true)
            notify_feishu "$message"
            ;;
    esac
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

parse_package_name() {
    local module_name=$1
    local package_name=$2
    local stem prefix version commit

    PARSED_PACKAGE_VERSION=""
    PARSED_PACKAGE_COMMIT=""

    stem=${package_name%.tar.gz}
    if [[ "$stem" == "$package_name" || "$stem" != "${module_name}-"* ]]; then
        return 1
    fi

    commit=${stem##*-}
    if [[ "${#commit}" -ne 7 || ! "$commit" =~ ^[0-9A-Za-z]{7}$ ]]; then
        return 1
    fi

    prefix=${stem%-${commit}}
    version=${prefix##*-v}
    if [[ "$version" == "$prefix" || ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi

    PARSED_PACKAGE_VERSION="$version"
    PARSED_PACKAGE_COMMIT="$commit"
    return 0
}

select_latest_local_package() {
    local module_name=$1
    shift
    local candidates=("$@")
    local item name version commit
    local max_key="" max_name="" max_version="" max_commit="" max_stem=""
    local version_key=""

    for item in "${candidates[@]}"; do
        name=$(basename "$item")
        if ! parse_package_name "$module_name" "$name"; then
            continue
        fi
        version="$PARSED_PACKAGE_VERSION"
        commit="$PARSED_PACKAGE_COMMIT"

        version_key=$(version_key_from_version "$version") || continue
        if [[ -z "$max_name" || "$version_key" > "$max_key" || ( "$version_key" == "$max_key" && "$name" > "$max_stem" ) ]]; then
            max_key="$version_key"
            max_name="$name"
            max_version="$version"
            max_commit="$commit"
            max_stem="$name"
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

    commit_matched_packages=()
    for package_name in "${output_package_names[@]}"; do
        if ! parse_package_name "$module_name" "$package_name"; then
            continue
        fi
        package_commit="$PARSED_PACKAGE_COMMIT"
        if [[ "$package_commit" == "$latest_commit" ]]; then
            commit_matched_packages+=("$package_name")
        fi
    done

    if [[ ${#commit_matched_packages[@]} -eq 0 ]]; then
        log "ERROR! no output package with latest commit (${latest_commit}) for ${module_name}"
        rm -f "$build_state_before"
        overall_status=1
        continue
    fi

    if ! select_latest_local_package "$module_name" "${commit_matched_packages[@]}"; then
        log "ERROR! failed to find valid output package for ${module_name} with commit ${latest_commit}"
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

    if [[ ! -f "$release_notes_script" ]]; then
        log "WARN! release notes script is missing: ${release_notes_script}"
    elif ! bash "$release_notes_script" --module "$module_name" >> "$LOGFILE" 2>&1; then
        log "WARN! release notes script failed for ${module_name}"
    else
        log "release notes generated for ${module_name}"
    fi

    package_hash_after=$(sha256sum "$package_file" | awk '{print $1}')
    package_hash_before=$(awk -v target="$package_filename" '$1 == target {print $2; exit}' "$build_state_before")
    rm -f "$build_state_before"
    if [[ -n "$package_hash_before" && "$package_hash_before" == "$package_hash_after" ]]; then
        log "package already exists for ${module_name}: ${package_filename} (unchanged, reuse)"
    fi

    cp -f "$package_file" "${package_root}/${package_filename}"
    log "package copied to ${package_root}/${package_filename}"

    if ! upload_with_retry "$package_filename"; then
        log "ERROR! upload still failed after 3 retries: ${package_filename}"
        notify_message "True" "$(format_error_notice \
            "${module_name}/${notify_type}" \
            "P2" \
            "处理中" \
            "产物上传连续 3 次失败：${package_filename}" \
            "新版本产物未能同步到制品仓库" \
            "构建已完成，故障出现在上传阶段" \
            "检查网络、WebDAV 配置和传输脚本后重试上传")"
        overall_status=1
        continue
    fi
done

log "\ncheck code status done. [$(date)]"
exit "$overall_status"
