#!/usr/bin/env bash
# Upload latest config backup files from /opt/backup to WebDAV.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1; pwd)
project_root=$(cd "${script_dir}/.." || exit 1; pwd)
backup_conf="${script_dir}/backup.conf"
backup_env_file="${script_dir}/.env"
transfer_file_script="${project_root}/common/transfer_file.sh"
feishu_common_sh="${project_root}/feishu-notify/common.sh"

# shellcheck disable=SC1091
source "${project_root}/common/common.sh"

if [[ -f "$feishu_common_sh" ]]; then
    # shellcheck disable=SC1090
    source "$feishu_common_sh"
fi

MODULES=()
backup_dir="${BACKUP_DIR:-/opt/backup}"
deploy_root="${DEPLOY_ROOT:-/opt/deploy}"
feishu_scene="backup_config"

usage() {
    cat <<EOF
Usage:
  $0 [module ...]
Notes:
  - when no module is provided, module list is read from ${backup_conf}
  - module backup settings are read from /data/<module>/backup.conf
  - WebDAV config is read from ${backup_env_file}
  - only the latest backup file from today or yesterday is uploaded
EOF
}

notify_feishu() {
    local message=$1

    if ! declare -F send_feishu_message >/dev/null 2>&1; then
        log "WARN! feishu notify helper is missing, skip notification: ${message}"
        return 0
    fi

    if ! send_feishu_message "$feishu_scene" "$message" >> "$LOGFILE" 2>&1; then
        log "WARN! failed to send feishu notification: ${message}"
    fi
}

load_backup_modules() {
    load_modules "$backup_conf" "$@"
}

load_module_backup_config() {
    local module_name=$1
    local module_conf="/data/${module_name}/backup.conf"

    if [[ ! -f "$module_conf" ]]; then
        log "ERROR! module backup config is missing: ${module_conf}"
        return 1
    fi

    unset BACKUP_CONF_FLAG BACKUP_CONF_PREFIX BACKUP_CONF_SUFFIX

    set -a
    # shellcheck disable=SC1090
    source "$module_conf"
    set +a

    BACKUP_CONF_FLAG=$(trim "${BACKUP_CONF_FLAG:-False}")
    BACKUP_CONF_PREFIX=$(trim "${BACKUP_CONF_PREFIX:-}")
    BACKUP_CONF_SUFFIX=$(trim "${BACKUP_CONF_SUFFIX:-}")
}

find_latest_config_backup_file() {
    local module_name=$1
    local pattern cutoff_epoch latest_line latest_epoch latest_file

    pattern="${BACKUP_CONF_PREFIX}${module_name}*${BACKUP_CONF_SUFFIX}"
    cutoff_epoch=$(date -d 'yesterday 00:00:00' '+%s')

    latest_line=$(
        find "$backup_dir" -maxdepth 1 -type f -name "$pattern" -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn \
            | awk 'NR == 1 { print }'
    )

    [[ -n "$latest_line" ]] || return 1

    latest_epoch=${latest_line%% *}
    latest_file=${latest_line#* }
    latest_epoch=${latest_epoch%.*}

    if (( latest_epoch < cutoff_epoch )); then
        log "latest config backup file is older than yesterday, skip upload: ${latest_file}"
        return 2
    fi

    printf '%s' "$latest_file"
}

upload_backup_file() {
    local backup_file=$1

    if [[ ! -f "$transfer_file_script" ]]; then
        log "ERROR! transfer file script is missing: ${transfer_file_script}"
        return 1
    fi

    if [[ ! -f "$backup_env_file" ]]; then
        log "ERROR! env file is missing: ${backup_env_file}"
        return 1
    fi

    WEBDAV_FILE_ENV_FILE="$backup_env_file" bash "$transfer_file_script" upload "$backup_file" >> "$LOGFILE" 2>&1
}

handle_module() {
    local module_name=$1
    local backup_file find_status

    if ! load_module_backup_config "$module_name"; then
        notify_feishu "CONFIG [ ${module_name} ] 配置备份读取失败，缺少 backup.conf"
        return 1
    fi

    case "$BACKUP_CONF_FLAG" in
        True|true)
            ;;
        False|false|"")
            log "skip config backup upload for ${module_name}, BACKUP_CONF_FLAG=${BACKUP_CONF_FLAG:-False}"
            notify_feishu "CONFIG [ ${module_name} ] 未启用配置文件备份上传"
            return 0
            ;;
        *)
            log "ERROR! invalid BACKUP_CONF_FLAG for ${module_name}: ${BACKUP_CONF_FLAG}, expected True or False"
            notify_feishu "CONFIG [ ${module_name} ] 配置备份参数错误，BACKUP_CONF_FLAG=${BACKUP_CONF_FLAG}"
            return 1
            ;;
    esac

    if [[ ! -d "$backup_dir" ]]; then
        log "ERROR! backup directory is missing: ${backup_dir}"
        notify_feishu "CONFIG [ ${module_name} ] 配置备份目录不存在：${backup_dir}"
        return 1
    fi

    find_status=0
    backup_file=$(find_latest_config_backup_file "$module_name") || find_status=$?
    case "$find_status" in
        0)
            ;;
        1)
            log "no config backup file found for module: ${module_name}"
            notify_feishu "CONFIG [ ${module_name} ] 没有需要上传的配置备份文件"
            return 0
            ;;
        2)
            notify_feishu "CONFIG [ ${module_name} ] 最近配置备份文件早于昨日，无需上传"
            return 0
            ;;
        *)
            log "ERROR! failed to find config backup file for module: ${module_name}"
            notify_feishu "CONFIG [ ${module_name} ] 查找配置备份文件失败"
            return 1
            ;;
    esac

    log "upload latest config backup file for ${module_name}: ${backup_file}"
    if upload_backup_file "$backup_file"; then
        notify_feishu "CONFIG [ ${module_name} ] 配置备份文件 ${backup_file} 上传成功"
        return 0
    fi

    notify_feishu "CONFIG [ ${module_name} ] 配置备份文件 ${backup_file} 上传失败"
    return 1
}

main() {
    local module_name overall_status=0

    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    init_log_file "upload-config-backup.log"

    load_backup_modules "$@" || exit 1

    for module_name in "${MODULES[@]}"; do
        log "handle config backup module [${module_name}]"
        if ! handle_module "$module_name"; then
            overall_status=1
        fi
    done

    exit "$overall_status"
}

main "$@"
