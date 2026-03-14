#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_TEMPLATE_FILE="${SCRIPT_DIR}/.env.template"
ENV_FILE="${SCRIPT_DIR}/.env"
SERVICE_NAME="postgres"

usage() {
  cat <<'EOF'
Usage:
  ./database.sh generate-env
  ./database.sh create-db -d <db_name> -u <user_name>
  ./database.sh create-db <db_name> -u <user_name>

Commands:
  generate-env           Generate .env from .env.template and auto-generate POSTGRES_PASSWORD
  create-db              Create a new database after checks

Options for create-db:
  -d <db_name>           Database name (required)
  -u <user_name>         Owner username (required)
  -h                     Show help
EOF
}

error() {
  echo "ERROR: $*" >&2
}

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 24
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
  fi
}

is_valid_identifier() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]
}

require_docker_compose() {
  if ! command -v docker >/dev/null 2>&1; then
    error "docker command not found."
    exit 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    error "docker compose is not available."
    exit 1
  fi
}

read_env_var() {
  local key="$1"
  local value=""

  value="$(
    awk -v k="${key}" '
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*$/ { next }
      {
        line = $0
        split(line, parts, "=")
        raw_key = parts[1]
        sub(/^[[:space:]]*export[[:space:]]+/, "", raw_key)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", raw_key)
        if (raw_key == k) {
          sub(/^[^=]*=/, "", line)
          val = line
        }
      }
      END {
        if (val == "") exit 1
        print val
      }
    ' "${ENV_FILE}"
  )" || return 1

  value="$(printf '%s' "${value}" | sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  if [ "${#value}" -ge 2 ]; then
    if [ "${value:0:1}" = "\"" ] && [ "${value: -1}" = "\"" ]; then
      value="${value:1:${#value}-2}"
    elif [ "${value:0:1}" = "'" ] && [ "${value: -1}" = "'" ]; then
      value="${value:1:${#value}-2}"
    fi
  fi

  printf '%s\n' "${value}"
}

load_env() {
  if [ ! -f "${ENV_FILE}" ]; then
    error ".env not found: ${ENV_FILE}. Run './database.sh generate-env' first."
    exit 1
  fi

  if ! POSTGRES_USER="$(read_env_var "POSTGRES_USER")"; then
    error "POSTGRES_USER is required in .env"
    exit 1
  fi
  if ! POSTGRES_PASSWORD="$(read_env_var "POSTGRES_PASSWORD")"; then
    error "POSTGRES_PASSWORD is required in .env"
    exit 1
  fi
  if ! POSTGRES_DB="$(read_env_var "POSTGRES_DB")"; then
    error "POSTGRES_DB is required in .env"
    exit 1
  fi

  : "${POSTGRES_USER:?POSTGRES_USER is required in .env}"
  : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required in .env}"
  : "${POSTGRES_DB:?POSTGRES_DB is required in .env}"
}

run_psql() {
  local sql="$1"
  docker compose exec -T "${SERVICE_NAME}" env PGPASSWORD="${POSTGRES_PASSWORD}" \
    psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -tAc "${sql}"
}

check_container_running() {
  local cid=""
  cid="$(docker compose ps -q "${SERVICE_NAME}" 2>/dev/null || true)"
  if [ -z "${cid}" ]; then
    return 1
  fi

  [ "$(docker inspect -f '{{.State.Running}}' "${cid}" 2>/dev/null || true)" = "true" ]
}

generate_env() {
  if [ ! -f "${ENV_TEMPLATE_FILE}" ]; then
    error ".env.template not found: ${ENV_TEMPLATE_FILE}"
    exit 1
  fi

  if [ -f "${ENV_FILE}" ]; then
    error ".env already exists: ${ENV_FILE}"
    echo "Tip: backup or remove .env and retry."
    exit 1
  fi

  local random_password=""
  random_password="$(generate_password)"

  cp "${ENV_TEMPLATE_FILE}" "${ENV_FILE}"
  if grep -q '^POSTGRES_PASSWORD=' "${ENV_FILE}"; then
    sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${random_password}/" "${ENV_FILE}"
  else
    printf '\nPOSTGRES_PASSWORD=%s\n' "${random_password}" >>"${ENV_FILE}"
  fi

  chmod 600 "${ENV_FILE}" || true
  echo ".env generated successfully: ${ENV_FILE}"
}

next_sql_sequence() {
  local init_dir="${SCRIPT_DIR}/init.db"
  local max_sequence=0
  local file=""
  local file_name=""
  local sequence=""

  mkdir -p "${init_dir}"

  shopt -s nullglob
  for file in "${init_dir}"/*.sql; do
    file_name="$(basename "${file}")"
    if [[ "${file_name}" =~ ^([0-9]+).*\.sql$ ]]; then
      sequence=$((10#${BASH_REMATCH[1]}))
      if (( sequence > max_sequence )); then
        max_sequence="${sequence}"
      fi
    fi
  done
  shopt -u nullglob

  printf '%02d\n' "$((max_sequence + 1))"
}

write_init_db_sql() {
  local sql_file="$1"
  local db_name="$2"
  local db_owner="$3"
  local create_user_sql="$4"

  cat >"${sql_file}" <<EOF
-- 根据 init.db.template/01.sql 生成
${create_user_sql}
CREATE DATABASE "${db_name}" OWNER "${db_owner}";

GRANT ALL PRIVILEGES ON DATABASE "${db_name}" TO "${db_owner}";

\connect "${db_name}"
CREATE EXTENSION IF NOT EXISTS btree_gist;
EOF
}

run_psql_file() {
  local container_sql_file="$1"
  docker compose exec -T "${SERVICE_NAME}" env PGPASSWORD="${POSTGRES_PASSWORD}" \
    psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -f "${container_sql_file}"
}

create_database() {
  local db_name=""
  local db_owner=""
  local init_dir="${SCRIPT_DIR}/init.db"
  local template_file="${SCRIPT_DIR}/init.db.template/01.sql"
  local sequence=""
  local sql_file_name=""
  local sql_file_path=""
  local container_sql_file=""

  OPTIND=1
  while getopts ":d:u:h" opt; do
    case "${opt}" in
      d)
        db_name="${OPTARG}"
        ;;
      u)
        db_owner="${OPTARG}"
        ;;
      h)
        usage
        exit 0
        ;;
      :)
        error "Option -${OPTARG} requires an argument."
        exit 1
        ;;
      \?)
        error "Unknown option: -${OPTARG}"
        usage
        exit 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if [ -z "${db_name}" ] && [ $# -ge 1 ]; then
    db_name="$1"
    shift
  fi
  if [ $# -gt 0 ]; then
    error "Unexpected arguments: $*"
    usage
    exit 1
  fi

  if [ -z "${db_name}" ]; then
    error "Database name is required. Use -d <db_name>."
    usage
    exit 1
  fi
  if [ -z "${db_owner}" ]; then
    error "Username is required. Use -u <user_name>."
    usage
    exit 1
  fi
  if ! is_valid_identifier "${db_name}"; then
    error "Invalid database name '${db_name}'. Use letters/numbers/underscore/hyphen and start with a letter or underscore."
    exit 1
  fi
  if ! is_valid_identifier "${db_owner}"; then
    error "Invalid username '${db_owner}'. Use letters/numbers/underscore/hyphen and start with a letter or underscore."
    exit 1
  fi
  if [ ! -f "${template_file}" ]; then
    error "Template SQL not found: ${template_file}"
    exit 1
  fi

  load_env

  require_docker_compose

  if ! check_container_running; then
    error "PostgreSQL container is not running."
    echo "Tip: run 'docker compose up -d' in ${SCRIPT_DIR}"
    exit 1
  fi

  if ! run_psql "SELECT 1;" >/dev/null 2>&1; then
    error "PostgreSQL is not ready yet."
    exit 1
  fi

  local db_exists=""
  db_exists="$(run_psql "SELECT 1 FROM pg_database WHERE datname='${db_name}';" | tr -d '[:space:]')"
  if [ "${db_exists}" = "1" ]; then
    error "Database '${db_name}' already exists."
    exit 1
  fi

  local owner_exists=""
  owner_exists="$(run_psql "SELECT 1 FROM pg_roles WHERE rolname='${db_owner}';" | tr -d '[:space:]')"
  if [ "${owner_exists}" = "1" ]; then
    error "Username '${db_owner}' already exists. Please choose a different username."
    exit 1
  fi

  local user_password=""
  local create_user_sql=""
  user_password="$(generate_password)"
  create_user_sql="CREATE USER \"${db_owner}\" WITH PASSWORD '${user_password}';"

  sequence="$(next_sql_sequence)"
  sql_file_name="${sequence}${db_name}.sql"
  sql_file_path="${init_dir}/${sql_file_name}"
  container_sql_file="/docker-entrypoint-initdb.d/${sql_file_name}"

  write_init_db_sql "${sql_file_path}" "${db_name}" "${db_owner}" "${create_user_sql}"
  run_psql_file "${container_sql_file}" >/dev/null

  echo "Database '${db_name}' created successfully. Owner: ${db_owner}"
  echo "SQL file generated: ${sql_file_path}"
  echo "Credentials:"
  echo "  username: ${db_owner}"
  echo "  password: ${user_password}"
}

main() {
  cd "${SCRIPT_DIR}"

  local cmd="${1:-}"
  case "${cmd}" in
    generate-env)
      generate_env
      ;;
    create-db)
      shift
      create_database "$@"
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      error "Unknown command: ${cmd}"
      usage
      exit 1
      ;;
  esac
}

main "$@"
