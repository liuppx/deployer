#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  source .env
fi

bind_address="${ONLYOFFICE_BIND_ADDRESS:-127.0.0.1}"
port="${ONLYOFFICE_PORT:-18088}"

docker compose ps
curl --fail --silent --show-error "http://${bind_address}:${port}/healthcheck"
echo
