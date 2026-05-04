#!/usr/bin/env bash

feishu_notify_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
feishu_reminder_script="$feishu_notify_dir/feishu_reminder.py"

load_feishu_notify_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

feishu_notify_load_config() {
  if [[ "${FEISHU_NOTIFY_CONFIG_LOADED:-false}" == "true" ]]; then
    return 0
  fi

  load_feishu_notify_env_file "$feishu_notify_dir/.env"
  FEISHU_NOTIFY_CONFIG_LOADED="true"
  export FEISHU_NOTIFY_CONFIG_LOADED
}

send_feishu_message() {
  local scene="$1"
  local message="$2"

  feishu_notify_load_config

  [[ -f "$feishu_reminder_script" ]] || {
    echo "cannot find script：$feishu_reminder_script" >&2
    return 1
  }

  python3 "$feishu_reminder_script" "$scene" "$message"
}
