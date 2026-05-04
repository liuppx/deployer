#!/usr/bin/env bash
# compare remote and local versions, then download and upgrade modules if needed

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

init_log_file "upgrade.log"

config_file="${script_dir}/modules.conf"
env_file="${script_dir}/.env"
package_root="/opt/package"
deploy_root="/opt/deploy"
transfer_script="${script_dir}/transfer_packages.sh"
dingtalk_script="${script_dir}/../dingtalk-notify/dingtalk_reminder.py"
dingtalk_scene="upgrade_service"
dingtalk_force_at="True"
feishu_scene="upgrade_service"
overall_status=0
notify_type="版本升级"

if [[ -f "$env_file" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "$env_file"
    set +a
fi

# True: read *_RECEIVER from .env and @userIds; False: no @
dingtalk_need_at="${DINGTALK_NEED_AT:-False}"
notify_from="${NOTIFY_FROM:-}"

usage() {
    log "Usage: $0"
    log "Read modules from ${config_file}, compare remote/latest and local/current, then upgrade when needed."
}

if [[ -z "${notify_from}" ]]; then
    notify_from=$(hostname)
fi

message_head="通知类型: ${notify_type} 
通知来源: ${notify_from} 
通知内容: "

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

    notify_dingtalk "$need_at" "$message"
    notify_feishu "$message"
}

notify_info() {
    local message=$1
    notify_message "$dingtalk_need_at" "$message"
}

notify_alert() {
    local message=$1
    notify_message "$dingtalk_force_at" "$message"
}

if [[ $# -ne 0 ]]; then
    usage
    exit 1
fi

load_modules "$config_file" || {
    usage
    exit 1
}

select_latest_by_fixed_short_commit() {
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

        # Parse from right side with fixed short commit length (7).
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

find_current_version_from_deploy_dirs() {
    local module_name=$1
    local candidate_dirs=()
    local dir

    for dir in "${deploy_root}/${module_name}-"*; do
        if [[ -d "$dir" ]]; then
            candidate_dirs+=("$(basename "$dir")")
        fi
    done

    if [[ ${#candidate_dirs[@]} -eq 0 ]]; then
        return 1
    fi

    select_latest_by_fixed_short_commit "$module_name" "${candidate_dirs[@]}"
}

resolve_webdav_dir_url_from_env() {
    local base_url prefix remote_dir custom_dir

    custom_dir=$(trim "${WEBDAV_DIR_URL:-}")
    if [[ -n "$custom_dir" ]]; then
        WEBDAV_DIR_URL="${custom_dir%/}"
        return 0
    fi

    base_url=$(trim "${WEBDAV_BASE_URL:-https://webdav.yeying.pub/dav/personal/}")
    prefix=$(trim "${WEBDAV_PREFIX:-}")
    remote_dir=$(trim "${WEBDAV_REMOTE_DIR:-public}")

    base_url="${base_url%/}"
    prefix="${prefix#/}"
    prefix="${prefix%/}"
    remote_dir="${remote_dir#/}"
    remote_dir="${remote_dir%/}"

    WEBDAV_DIR_URL="$base_url"
    if [[ -n "$prefix" ]]; then
        WEBDAV_DIR_URL="${WEBDAV_DIR_URL}/${prefix}"
    fi
    if [[ -n "$remote_dir" ]]; then
        WEBDAV_DIR_URL="${WEBDAV_DIR_URL}/${remote_dir}"
    fi
}

if [[ ! -f "$transfer_script" ]]; then
    log "ERROR! transfer script is missing: ${transfer_script}"
    exit 1
fi

load_webdav_env "$env_file" || exit 1
resolve_webdav_dir_url_from_env
mkdir -p "$package_root" "$deploy_root"
log "webdav remote dir: ${WEBDAV_DIR_URL}/"
log "webdav username: ${WEBDAV_USERNAME:-<empty>}"

mapfile -t remote_files < <(webdav_list_files) || exit 1
log "remote files count: ${#remote_files[@]}"
log "\nbegin upgrade [$(date)]"

for module_name in "${MODULES[@]}"; do
    log "\nhandle module [${module_name}]"

    remote_candidates=()
    for remote_name in "${remote_files[@]}"; do
        if [[ "$remote_name" == "${module_name}-"*.tar.gz ]]; then
            remote_candidates+=("$remote_name")
        fi
    done

    if [[ ${#remote_candidates[@]} -eq 0 ]]; then
        log "ERROR! no remote package found for ${module_name}"
        notify_alert "${message_head} ${module_name}: no remote package found"
        if [[ ${#remote_files[@]} -gt 0 ]]; then
            log "remote file samples:"
            printf '%s\n' "${remote_files[@]:0:50}" | tee -a "$LOGFILE" >/dev/null
        fi
        overall_status=1
        continue
    fi

    if ! select_latest_by_fixed_short_commit "$module_name" "${remote_candidates[@]}"; then
        log "ERROR! failed to parse remote package version for ${module_name}"
        notify_alert "${message_head} ${module_name}: failed to parse remote package version"
        overall_status=1
        continue
    fi

    target_filename="$SELECTED_NAME"
    target_version="$SELECTED_VERSION"
    target_dir_name="${target_filename%.tar.gz}"
    log "target package: ${target_filename}"
    log "target version: ${target_version}"

    current_version=""
    if find_current_version_from_deploy_dirs "$module_name"; then
        current_version="$SELECTED_VERSION"
        log "current version: ${current_version}"
    else
        log "ERROR! current version directory not found in ${deploy_root} for ${module_name}"
        notify_alert "${message_head} ${module_name}: current version directory not found in ${deploy_root}"
        overall_status=1
        continue
    fi

    if ! version_gt "$target_version" "$current_version"; then
        log "no upgrade needed for ${module_name}, current version ${current_version} is up to date"
        notify_info "${message_head} ${module_name}: no upgrade needed, current version ${current_version} is up to date"
        continue
    fi

    log "upgrade needed for ${module_name}: ${current_version} -> ${target_version}"

    if ! bash "$transfer_script" download "$target_filename" >> "$LOGFILE" 2>&1; then
        log "ERROR! failed to download package: ${target_filename}"
        notify_alert "${message_head} ${module_name}: failed to download package ${target_filename}"
        overall_status=1
        continue
    fi

    package_file="${package_root}/${target_filename}"
    if [[ ! -f "$package_file" ]]; then
        log "ERROR! downloaded package is missing: ${package_file}"
        notify_alert "${message_head} ${module_name}: downloaded package is missing ${target_filename}"
        overall_status=1
        continue
    fi

    if ! ensure_extracted_dir "$package_file" "$deploy_root" "$target_dir_name"; then
        notify_alert "${message_head} ${module_name}: failed to extract package ${target_filename}"
        overall_status=1
        continue
    fi
    log "package extracted to ${EXTRACTED_DIR}"

    upgrade_script="${script_dir}/upgrade_${module_name}.sh"
    if [[ ! -f "$upgrade_script" ]]; then
        log "ERROR! upgrade script is missing: ${upgrade_script}"
        notify_alert "${message_head} ${module_name}: upgrade script is missing ${upgrade_script}"
        overall_status=1
        continue
    fi

    if ! bash "$upgrade_script" "$current_version" "$target_version" >> "$LOGFILE" 2>&1; then
        log "ERROR! upgrade script failed for ${module_name}"
        notify_alert "${message_head} ${module_name}: upgrade script failed"
        overall_status=1
        continue
    fi

    log "upgrade finished for ${module_name}: ${current_version} -> ${target_version}"
    notify_info "${message_head} ${module_name} upgrade finished: ${current_version} -> ${target_version}"
done

log "\nupgrade done. [$(date)]"
exit "$overall_status"
