#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

REDIS_PASSWORD="${REDIS_PASSWORD:-}"
REDIS_NODES="${REDIS_NODES:-127.0.0.1:6379}"
REDIS_CLI_MODE="${REDIS_CLI_MODE:-auto}"
REDIS_EXPECT_MODE="${REDIS_EXPECT_MODE:-auto}"

if [[ -z "${REDIS_PASSWORD}" ]]; then
  echo "ERROR: REDIS_PASSWORD is empty. Please set it in ${ENV_FILE}."
  exit 1
fi

if [[ "${REDIS_CLI_MODE}" != "auto" && "${REDIS_CLI_MODE}" != "local" && "${REDIS_CLI_MODE}" != "docker" ]]; then
  echo "ERROR: REDIS_CLI_MODE must be one of: auto, local, docker"
  exit 1
fi

if [[ "${REDIS_EXPECT_MODE}" != "auto" && "${REDIS_EXPECT_MODE}" != "cluster" && "${REDIS_EXPECT_MODE}" != "standalone" ]]; then
  echo "ERROR: REDIS_EXPECT_MODE must be one of: auto, cluster, standalone"
  exit 1
fi

if [[ "${REDIS_CLI_MODE}" == "auto" ]]; then
  if command -v redis-cli >/dev/null 2>&1; then
    REDIS_CLI_MODE="local"
  else
    REDIS_CLI_MODE="docker"
  fi
fi

if [[ "${REDIS_CLI_MODE}" == "local" ]]; then
  if ! command -v redis-cli >/dev/null 2>&1; then
    echo "ERROR: redis-cli not found, please install it or set REDIS_CLI_MODE=docker."
    exit 1
  fi
  REDIS_CLI_BASE=(redis-cli --no-auth-warning)
else
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker command not found, cannot use REDIS_CLI_MODE=docker."
    exit 1
  fi
  if ! docker compose -f "${SCRIPT_DIR}/docker-compose.yml" exec -T redis redis-cli --version >/dev/null 2>&1; then
    echo "ERROR: cannot run 'docker compose exec redis redis-cli'. Make sure redis service is up."
    exit 1
  fi
  REDIS_CLI_BASE=(docker compose -f "${SCRIPT_DIR}/docker-compose.yml" exec -T redis redis-cli --no-auth-warning)
fi

IFS=',' read -r -a NODES <<< "${REDIS_NODES}"
if [[ "${#NODES[@]}" -eq 0 ]]; then
  echo "ERROR: REDIS_NODES is empty. Example: 127.0.0.1:6379,127.0.0.1:6380"
  exit 1
fi

FIRST_NODE="${NODES[0]}"
REDIS_HOST="${FIRST_NODE%:*}"
REDIS_PORT="${FIRST_NODE##*:}"

if [[ -z "${REDIS_HOST}" || -z "${REDIS_PORT}" || "${REDIS_HOST}" == "${REDIS_PORT}" ]]; then
  echo "ERROR: Invalid REDIS_NODES format. Use host:port,host:port"
  exit 1
fi

redis_cmd() {
  "${REDIS_CLI_BASE[@]}" -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" "$@"
}

redis_cluster_cmd() {
  "${REDIS_CLI_BASE[@]}" -c -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" "$@"
}

echo "Testing Redis cluster from node ${REDIS_HOST}:${REDIS_PORT} (cli_mode=${REDIS_CLI_MODE})"

for NODE in "${NODES[@]}"; do
  NODE_HOST="${NODE%:*}"
  NODE_PORT="${NODE##*:}"
  NODE_PING="$("${REDIS_CLI_BASE[@]}" -h "${NODE_HOST}" -p "${NODE_PORT}" -a "${REDIS_PASSWORD}" ping || true)"
  if [[ "${NODE_PING}" != "PONG" ]]; then
    echo "FAIL: Node ${NODE_HOST}:${NODE_PORT} ping failed. Response: ${NODE_PING}"
    exit 1
  fi
done
echo "PASS: All REDIS_NODES are reachable"

PING_RESULT="$(redis_cmd ping || true)"
if [[ "${PING_RESULT}" != "PONG" ]]; then
  echo "FAIL: PING failed. Response: ${PING_RESULT}"
  exit 1
fi
echo "PASS: PING = PONG"

CLUSTER_INFO="$(redis_cmd cluster info || true)"
if [[ -z "${CLUSTER_INFO}" ]]; then
  echo "FAIL: CLUSTER INFO failed. Response: ${CLUSTER_INFO}"
  exit 1
fi

if grep -qi "cluster support disabled" <<< "${CLUSTER_INFO}"; then
  if [[ "${REDIS_EXPECT_MODE}" == "cluster" ]]; then
    echo "FAIL: current Redis is standalone (cluster support disabled), but REDIS_EXPECT_MODE=cluster."
    exit 1
  fi

  TEST_KEY="standalone:test:$(date +%s)"
  TEST_VAL="ok-$(date +%s)"
  SET_RESULT="$(redis_cmd set "${TEST_KEY}" "${TEST_VAL}" EX 60 || true)"
  if [[ "${SET_RESULT}" != "OK" ]]; then
    echo "FAIL: Standalone SET test failed. Response: ${SET_RESULT}"
    exit 1
  fi
  GET_RESULT="$(redis_cmd get "${TEST_KEY}" || true)"
  if [[ "${GET_RESULT}" != "${TEST_VAL}" ]]; then
    echo "FAIL: Standalone GET mismatch. expected='${TEST_VAL}' got='${GET_RESULT}'"
    exit 1
  fi
  echo "PASS: Detected standalone Redis and read/write test passed"
  echo "SUCCESS: Redis is available in standalone mode."
  exit 0
fi

if [[ "${CLUSTER_INFO}" == *"ERR"* ]]; then
  echo "FAIL: CLUSTER INFO failed. Response: ${CLUSTER_INFO}"
  exit 1
fi

if [[ "${REDIS_EXPECT_MODE}" == "standalone" ]]; then
  echo "FAIL: current Redis is cluster mode, but REDIS_EXPECT_MODE=standalone."
  exit 1
fi

CLUSTER_STATE="$(awk -F: '/^cluster_state:/{print $2}' <<< "${CLUSTER_INFO}" | tr -d '\r')"
if [[ "${CLUSTER_STATE}" != "ok" ]]; then
  echo "FAIL: cluster_state is '${CLUSTER_STATE}', expected 'ok'."
  exit 1
fi
echo "PASS: cluster_state = ok"

CLUSTER_NODES_OUTPUT="$(redis_cmd cluster nodes || true)"
if [[ -z "${CLUSTER_NODES_OUTPUT}" || "${CLUSTER_NODES_OUTPUT}" == *"ERR"* ]]; then
  echo "FAIL: CLUSTER NODES failed. Response: ${CLUSTER_NODES_OUTPUT}"
  exit 1
fi

if grep -E "(fail|handshake|noaddr)" <<< "${CLUSTER_NODES_OUTPUT}" >/dev/null 2>&1; then
  echo "FAIL: Found unhealthy cluster node flags:"
  grep -E "(fail|handshake|noaddr)" <<< "${CLUSTER_NODES_OUTPUT}" || true
  exit 1
fi
echo "PASS: All cluster nodes look healthy"

TEST_KEY="cluster:test:$(date +%s)"
TEST_VAL="ok-$(date +%s)"

SET_RESULT="$(redis_cluster_cmd set "${TEST_KEY}" "${TEST_VAL}" EX 60 || true)"
if [[ "${SET_RESULT}" != "OK" ]]; then
  echo "FAIL: SET test key failed. Response: ${SET_RESULT}"
  exit 1
fi

GET_RESULT="$(redis_cluster_cmd get "${TEST_KEY}" || true)"
if [[ "${GET_RESULT}" != "${TEST_VAL}" ]]; then
  echo "FAIL: GET test key mismatch. expected='${TEST_VAL}' got='${GET_RESULT}'"
  exit 1
fi
echo "PASS: Cluster write/read test passed"

echo "SUCCESS: Redis cluster is available."
