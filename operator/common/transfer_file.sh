#!/usr/bin/env bash
# Upload one local file to WebDAV or download all remote files into a local directory.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1; pwd)
project_root=$(cd "${script_dir}/.." || exit 1; pwd)

# shellcheck disable=SC1091
source "${project_root}/common/common.sh"

env_file="${WEBDAV_FILE_ENV_FILE:-${script_dir}/.env}"
webdav_dir_url=""
AUTH_ARGS=()

usage() {
    cat <<EOF
Usage:
  $0 upload <absolute_file_path>
  $0 download <local_directory>
Notes:
  - upload checks that the local file exists
  - download checks that the local directory exists, then downloads all files from WEBDAV_FILE_BASE_URL
  - auth is read from ${env_file}: WEBDAV_FILE_BASE_URL, WEBDAV_FILE_AK, WEBDAV_FILE_SK
EOF
}

load_webdav_config() {
    local base_url

    if [[ ! -f "$env_file" ]]; then
        log "ERROR! env file is missing: ${env_file}"
        return 1
    fi

    # shellcheck disable=SC1090
    set -a
    source "$env_file"
    set +a

    if [[ -z "${WEBDAV_FILE_AK:-}" || -z "${WEBDAV_FILE_SK:-}" ]]; then
        log "ERROR! set WEBDAV_FILE_AK and WEBDAV_FILE_SK in ${env_file}."
        return 1
    fi

    base_url=$(trim "${WEBDAV_FILE_BASE_URL:-}")
    base_url="${base_url%/}"

    if [[ -z "$base_url" ]]; then
        log "ERROR! set WEBDAV_FILE_BASE_URL in ${env_file}."
        return 1
    fi

    AUTH_ARGS=(-u "${WEBDAV_FILE_AK}:${WEBDAV_FILE_SK}")
    webdav_dir_url="$base_url"
}

build_remote_url() {
    local dir_url=$1
    local target_name=$2
    local encoded_name

    encoded_name=$(urlencode_component "$target_name") || return 1
    printf '%s/%s' "${dir_url%/}" "$encoded_name"
}

ensure_remote_dir_recursive() {
    local dir_url=$1
    local status check_status

    check_status=$(curl -sS -o /dev/null -w "%{http_code}" -X PROPFIND -H "Depth: 0" "${AUTH_ARGS[@]}" "$dir_url")
    case "$check_status" in
        200|207|301|302|307|308)
            return 0
            ;;
        401|403)
            log "ERROR! authentication failed while checking remote dir: ${dir_url}"
            return 1
            ;;
    esac

    status=$(curl -sS -o /dev/null -w "%{http_code}" -X MKCOL "${AUTH_ARGS[@]}" "$dir_url")
    case "$status" in
        200|201|204|301|302|307|308|405)
            return 0
            ;;
        401|403)
            log "ERROR! authentication failed while ensuring remote dir: ${dir_url}"
            return 1
            ;;
        409)
            log "ERROR! parent directory is missing for remote dir: ${dir_url}"
            return 1
            ;;
        *)
            log "ERROR! failed to ensure remote dir ${dir_url}, mkcol=${status}, propfind=${check_status}"
            return 1
            ;;
    esac
}

list_remote_files() {
    local response status body

    response=$(curl -sS -X PROPFIND -H "Depth: 1" "${AUTH_ARGS[@]}" "${webdav_dir_url}/" -w "\n%{http_code}")
    status="${response##*$'\n'}"
    body="${response%$'\n'*}"

    case "$status" in
        200|207)
            ;;
        401|403)
            log_err "ERROR! authentication failed for ${webdav_dir_url}/"
            return 1
            ;;
        404)
            log_err "ERROR! remote directory not found: ${webdav_dir_url}/"
            return 1
            ;;
        *)
            log_err "ERROR! failed to list remote directory (${webdav_dir_url}/), http status ${status}"
            return 1
            ;;
    esac

    printf '%s' "$body" | python3 -c '
import os
import sys
import urllib.parse
import xml.etree.ElementTree as ET

data = sys.stdin.read()
if not data.strip():
    sys.exit(0)

try:
    root = ET.fromstring(data)
except Exception:
    sys.exit(0)

seen = set()

def emit(name: str) -> None:
    if not name or name in seen:
        return
    seen.add(name)
    print(name)

for response in root.iter():
    if not response.tag.endswith("response"):
        continue
    href = ""
    is_collection = False
    for elem in response.iter():
        if elem.tag.endswith("href") and elem.text:
            href = elem.text.strip()
        if elem.tag.endswith("collection"):
            is_collection = True
    if is_collection or not href:
        continue
    parsed = urllib.parse.urlparse(href)
    path = parsed.path if parsed.scheme else href
    path = urllib.parse.unquote(path)
    emit(os.path.basename(path.rstrip("/")))
'
}

download_remote_file() {
    local filename=$1
    local target_dir=$2
    local remote_file_url tmpfile download_status

    remote_file_url=$(build_remote_url "$webdav_dir_url" "$filename") || {
        log "ERROR! failed to build remote url for ${filename}"
        return 1
    }

    tmpfile=$(mktemp "/tmp/${filename//[^A-Za-z0-9._-]/_}.XXXXXX")
    log "download file: ${remote_file_url}"
    download_status=$(curl -sS -o "$tmpfile" -w "%{http_code}" "${AUTH_ARGS[@]}" "$remote_file_url")
    case "$download_status" in
        200|206)
            mv -f "$tmpfile" "${target_dir%/}/${filename}"
            log "download success: ${target_dir%/}/${filename}"
            ;;
        401|403)
            rm -f "$tmpfile"
            log "ERROR! authentication failed during download: ${filename}"
            return 1
            ;;
        404)
            rm -f "$tmpfile"
            log "ERROR! remote file not found: ${filename}"
            return 1
            ;;
        *)
            if [[ -s "$tmpfile" ]]; then
                log "server response: $(tr '\n' ' ' < "$tmpfile" | head -c 500)"
            fi
            rm -f "$tmpfile"
            log "ERROR! download failed for ${filename}, http status ${download_status}"
            return 1
            ;;
    esac
}

if [[ $# -eq 1 ]]; then
    arg1=$(trim "$1")
    if [[ "$arg1" == "-h" || "$arg1" == "--help" ]]; then
        usage
        exit 0
    fi
fi

if [[ $# -ne 2 ]]; then
    usage
    exit 1
fi

init_log_file "transfer-file.log"

operation=$(trim "$1")
target=$(trim "$2")

if [[ -z "$operation" || -z "$target" ]]; then
    usage
    exit 1
fi

load_webdav_config || exit 1

case "$operation" in
    upload)
        if [[ "$target" != /* ]]; then
            log "ERROR! upload requires an absolute file path: ${target}"
            exit 1
        fi
        if [[ ! -f "$target" ]]; then
            log "ERROR! local file is missing: ${target}"
            exit 2
        fi

        if ! ensure_remote_dir_recursive "$webdav_dir_url"; then
            exit 4
        fi

        filename=$(basename "$target")
        remote_file_url=$(build_remote_url "$webdav_dir_url" "$filename") || {
            log "ERROR! failed to build remote url for ${filename}"
            exit 1
        }

        log "upload file: ${target} -> ${remote_file_url}"
        upload_body_file=$(mktemp "/tmp/upload_${filename//[^A-Za-z0-9._-]/_}.XXXXXX")
        upload_status=$(curl -sS -o "$upload_body_file" -w "%{http_code}" \
            -X PUT "${AUTH_ARGS[@]}" --data-binary @"$target" "$remote_file_url")

        case "$upload_status" in
            200|201|204)
                rm -f "$upload_body_file"
                log "upload success: ${filename}"
                ;;
            401|403)
                rm -f "$upload_body_file"
                log "ERROR! authentication failed during upload: ${filename}"
                exit 4
                ;;
            301|302|307|308)
                rm -f "$upload_body_file"
                log "ERROR! upload redirected (http ${upload_status}), set exact WEBDAV_FILE_BASE_URL in ${env_file}"
                exit 4
                ;;
            404)
                rm -f "$upload_body_file"
                log "ERROR! remote path not found: ${webdav_dir_url}/"
                exit 4
                ;;
            412)
                rm -f "$upload_body_file"
                log "ERROR! target file already exists: ${remote_file_url}"
                exit 4
                ;;
            *)
                if [[ -s "$upload_body_file" ]]; then
                    log "server response: $(tr '\n' ' ' < "$upload_body_file" | head -c 500)"
                fi
                rm -f "$upload_body_file"
                log "ERROR! upload failed for ${filename}, http status ${upload_status}"
                exit 4
                ;;
        esac
        ;;
    download)
        if [[ ! -d "$target" ]]; then
            log "ERROR! local directory is missing: ${target}"
            exit 2
        fi

        mapfile -t remote_files < <(list_remote_files)
        if [[ ${#remote_files[@]} -eq 0 ]]; then
            log "ERROR! no remote files found in ${webdav_dir_url}/"
            exit 5
        fi

        for filename in "${remote_files[@]}"; do
            download_remote_file "$filename" "$target" || exit 5
        done
        ;;
    *)
        usage
        exit 1
        ;;
esac
