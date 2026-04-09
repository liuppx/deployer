#!/usr/bin/env bash
# Monitor service error logs and send notifications

set -euo pipefail
shopt -s nullglob

script_dir=$(cd "$(dirname "$0")" || exit 1; pwd)
# shellcheck disable=SC1091
source "${script_dir}/../upgrade/common.sh"

init_log_file "monitor.log"

config_file="${script_dir}/modules.conf"
deploy_root="/opt/deploy"
temp_dir="/tmp"
dingtalk_script="${script_dir}/../dingtalk-notify/dingtalk_reminder.py"
dingtalk_scene="monitor_service"
# True: read *_RECEIVER from .env and @userIds; False: no @
dingtalk_need_at="${DINGTALK_NEED_AT:-False}"
dingtalk_force_at="True"
overall_status=0

usage() {
    log "Usage: $0"
    log "Read modules from ${config_file}, monitor error logs, and send notifications when needed."
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

notify_alert() {
    local message=$1
    notify_dingtalk "$dingtalk_force_at" "$message"
}

notify_info() {
    local message=$1
    notify_dingtalk "$dingtalk_need_at" "$message"
}

# Find the current running directory for a module (highest version)
find_current_deploy_dir() {
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

# Compare error logs and return diff
get_error_diff() {
    local new_log=$1
    local old_log=$2
    local diff_output

    if [[ ! -f "$new_log" ]]; then
        echo ""
        return 0
    fi

    local new_content
    new_content=$(cat "$new_log")

    if [[ -z "$new_content" ]]; then
        echo ""
        return 0
    fi

    if [[ ! -f "$old_log" ]]; then
        # Old log doesn't exist, return all new content
        echo "$new_content"
        return 0
    fi

    local old_content
    old_content=$(cat "$old_log")

    if [[ "$new_content" == "$old_content" ]]; then
        echo ""
        return 0
    fi

    # Find the difference using diff
    diff_output=$(diff "$old_log" "$new_log" 2>/dev/null) || true

    if [[ -z "$diff_output" ]]; then
        echo ""
        return 0
    fi

    # Extract lines starting with '>' which are the new lines
    echo "$diff_output" | grep '^>' | sed 's/^> //'
}

# Count lines in diff
count_diff_lines() {
    local diff_content=$1
    printf '%s\n' "$diff_content" | wc -l
}

if [[ $# -ne 0 ]]; then
    usage
    exit 1
fi

load_modules "$config_file" || {
    usage
    exit 1
}

log "\nbegin monitor [$(date)]"

for module_name in "${MODULES[@]}"; do
    log "\nhandle module [${module_name}]"

    # Find current running deploy directory
    if ! find_current_deploy_dir "$module_name"; then
        log "ERROR! current deploy directory not found in ${deploy_root} for ${module_name}"
        overall_status=1
        continue
    fi

    current_dir_name="$SELECTED_NAME"
    current_version="$SELECTED_VERSION"
    current_commit="$SELECTED_COMMIT"
    current_dir="${deploy_root}/${current_dir_name}"

    log "current deploy directory: ${current_dir_name}"
    log "current version: ${current_version}"
    log "current commit: ${current_commit}"

    # Check error log
    error_log="${current_dir}/logs/error.log"
    temp_error_log="${temp_dir}/${module_name}-error.log"

    log "checking error log: ${error_log}"
    touch "$temp_error_log"

    # Get the diff
    diff_content=$(get_error_diff "$error_log" "$temp_error_log")

    if [[ -z "$diff_content" ]]; then
        log "no new error logs for ${module_name}"
        # Update temp log to current state even if empty
        if [[ -f "$error_log" ]]; then
            cp "$error_log" "$temp_error_log"
        else
            : > "$temp_error_log"
        fi
        continue
    fi

    # Count diff lines
    diff_line_count=$(count_diff_lines "$diff_content")
    log "new error log lines: ${diff_line_count}"

    # Prepare message
    if [[ "$diff_line_count" -le 10 ]]; then
        # Send all diff content
        message="${current_dir_name} 新增错误日志如下：

${diff_content}"
        log "sending full diff notification for ${module_name}"
        notify_info "$message"
    else
        # Send only last 10 lines
        last_10_lines=$(tail -n 10 "$error_log")
        message="${current_dir_name} 部分错误日志如下，详情请登陆节点获取：

${last_10_lines}"
        log "sending partial diff notification for ${module_name}"
        notify_info "$message"
    fi

    # Update temp error log to current state
    if [[ -f "$error_log" ]]; then
        cp "$error_log" "$temp_error_log"
    else
        : > "$temp_error_log"
    fi
done

log "\nmonitor done. [$(date)]"
exit "$overall_status"
