#!/usr/bin/env bash
set -euo pipefail

: "${DATADOG_API_KEY:?DATADOG_API_KEY must be set}"
: "${DD_SITE:=datadoghq.com}"
: "${DATADOG_AGENT_NAME:=springboot-demo-datadog-agent}"
: "${DATADOG_AGENT_IMAGE:=gcr.io/datadoghq/agent:7}"
: "${PROD_NETWORK:=springboot-demo-main-network}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HTTP_CHECK_CONF="${REPO_ROOT}/deploy/datadog/http_check.d/conf.yaml"
DATADOG_RUN_DIR="${DATADOG_RUN_DIR:-/tmp/${DATADOG_AGENT_NAME}-run}"

if [ ! -f "${HTTP_CHECK_CONF}" ]; then
  echo "Datadog HTTP check config not found at ${HTTP_CHECK_CONF}" >&2
  exit 1
fi

mkdir -p "${DATADOG_RUN_DIR}"

if ! docker network inspect "${PROD_NETWORK}" >/dev/null 2>&1; then
  docker network create "${PROD_NETWORK}" >/dev/null
fi

docker rm -f "${DATADOG_AGENT_NAME}" >/dev/null 2>&1 || true

docker run -d \
  --name "${DATADOG_AGENT_NAME}" \
  --restart unless-stopped \
  --cgroupns host \
  --pid host \
  --network "${PROD_NETWORK}" \
  -e DD_API_KEY="${DATADOG_API_KEY}" \
  -e DD_SITE="${DD_SITE}" \
  -e DD_HOSTNAME="$(hostname)" \
  -e DD_LOGS_ENABLED=true \
  -e DD_PROCESS_CONFIG_PROCESS_COLLECTION_ENABLED=true \
  -e DD_PROCESS_CONFIG_CONTAINER_COLLECTION_ENABLED=true \
  -e DD_CONTAINER_EXCLUDE="name:${DATADOG_AGENT_NAME}" \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /var/lib/docker/containers:/var/lib/docker/containers:ro \
  -v /proc/:/host/proc/:ro \
  -v /sys/fs/cgroup/:/host/sys/fs/cgroup:ro \
  -v "${DATADOG_RUN_DIR}:/opt/datadog-agent/run:rw" \
  -v "${HTTP_CHECK_CONF}:/conf.d/http_check.d/conf.yaml:ro" \
  "${DATADOG_AGENT_IMAGE}" >/dev/null
