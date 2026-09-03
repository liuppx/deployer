#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but was not found." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose v2 is required but was not found." >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  echo "Missing .env. Copy .env.template to .env and set ONLYOFFICE_JWT_SECRET before starting." >&2
  exit 1
fi

# shellcheck disable=SC1091
source .env

if [[ "${ONLYOFFICE_JWT_SECRET:-}" == "" || "${ONLYOFFICE_JWT_SECRET:-}" == "change-me-to-a-long-random-secret" ]]; then
  echo "Please set ONLYOFFICE_JWT_SECRET in .env to a long random value." >&2
  exit 1
fi

docker compose up -d

bind_address="${ONLYOFFICE_BIND_ADDRESS:-127.0.0.1}"
port="${ONLYOFFICE_PORT:-18088}"

echo
echo "OnlyOffice Docs: http://${bind_address}:${port}"
echo "API script:      http://${bind_address}:${port}/web-apps/apps/api/documents/api.js"
docker compose ps
