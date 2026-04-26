#!/usr/bin/env bash
set -euo pipefail

: "${IMAGE_NAME:?IMAGE_NAME must be set}"
: "${IMAGE_TAG:?IMAGE_TAG must be set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PERF_IMAGE_REF="${PERF_IMAGE_REF:-${IMAGE_NAME}:${IMAGE_TAG}}"
PERF_ARTIFACT_DIR="${PERF_ARTIFACT_DIR:-target/performance}"
PERF_NETWORK="${PERF_NETWORK:-springboot-demo-perf-${IMAGE_TAG}-${PPID}}"
PERF_APP_CONTAINER_NAME="${PERF_APP_CONTAINER_NAME:-springboot-demo-perf-app-${IMAGE_TAG}-${PPID}}"
K6_IMAGE="${K6_IMAGE:-grafana/k6:0.49.0}"
CURL_IMAGE="${CURL_IMAGE:-curlimages/curl:8.12.1}"
K6_SCRIPT_PATH="${REPO_ROOT}/scripts/perf/load-test.js"

ARTIFACT_DIR_ABS="${REPO_ROOT}/${PERF_ARTIFACT_DIR}"
SUMMARY_JSON="${ARTIFACT_DIR_ABS}/k6-summary.json"
SUMMARY_TEXT="${ARTIFACT_DIR_ABS}/k6-summary.txt"
STATS_RAW="${ARTIFACT_DIR_ABS}/docker-stats.ndjson"
PROFILE_JSON="${ARTIFACT_DIR_ABS}/profile.json"

cleanup() {
  set +e

  if [ -n "${SAMPLER_PID:-}" ]; then
    kill "${SAMPLER_PID}" >/dev/null 2>&1 || true
    wait "${SAMPLER_PID}" >/dev/null 2>&1 || true
  fi

  docker rm -f "${PERF_APP_CONTAINER_NAME}" >/dev/null 2>&1 || true
  docker network rm "${PERF_NETWORK}" >/dev/null 2>&1 || true
}

wait_for_app() {
  local deadline=$((SECONDS + 60))

  while (( SECONDS < deadline )); do
    if docker run --rm --network "${PERF_NETWORK}" "${CURL_IMAGE}" \
      -fsS "http://${PERF_APP_CONTAINER_NAME}:8080/actuator/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
}

start_stats_sampler() {
  : > "${STATS_RAW}"

  (
    while docker inspect -f '{{.State.Running}}' "${PERF_APP_CONTAINER_NAME}" 2>/dev/null | grep -qx 'true'; do
      docker stats --no-stream --format '{{json .}}' "${PERF_APP_CONTAINER_NAME}" >> "${STATS_RAW}" 2>/dev/null || true
      sleep 1
    done
  ) &

  SAMPLER_PID=$!
}

write_profile_summary() {
  python3 - "${STATS_RAW}" "${PROFILE_JSON}" <<'PY'
import json
import re
import sys
from pathlib import Path

stats_path = Path(sys.argv[1])
profile_path = Path(sys.argv[2])

unit_multipliers = {
    "B": 1 / (1024 * 1024),
    "KiB": 1 / 1024,
    "MiB": 1,
    "GiB": 1024,
    "TiB": 1024 * 1024,
    "kB": 1 / 1000,
    "MB": 1,
    "GB": 1000,
}

def parse_cpu(value: str) -> float:
    value = (value or "0").strip().rstrip("%")
    return float(value or 0)

def parse_memory_mb(value: str) -> float:
    current = (value or "0B").split("/")[0].strip().replace(" ", "")
    match = re.match(r"([0-9.]+)([A-Za-z]+)", current)
    if not match:
        return 0.0
    amount = float(match.group(1))
    unit = match.group(2)
    return amount * unit_multipliers.get(unit, 0.0)

max_cpu = 0.0
max_memory = 0.0

if stats_path.exists():
    for raw_line in stats_path.read_text().splitlines():
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        entry = json.loads(raw_line)
        max_cpu = max(max_cpu, parse_cpu(entry.get("CPUPerc", "0")))
        max_memory = max(max_memory, parse_memory_mb(entry.get("MemUsage", "0B / 0B")))

profile = {
    "container_cpu_percent_max": round(max_cpu, 2),
    "container_memory_mb_max": round(max_memory, 2),
}

profile_path.write_text(json.dumps(profile, indent=2) + "\n")
PY
}

trap cleanup EXIT

mkdir -p "${ARTIFACT_DIR_ABS}"

if ! docker image inspect "${PERF_IMAGE_REF}" >/dev/null 2>&1; then
  echo "Local image ${PERF_IMAGE_REF} was not found. Build the app image before running performance tests." >&2
  exit 1
fi

docker network create "${PERF_NETWORK}" >/dev/null
docker rm -f "${PERF_APP_CONTAINER_NAME}" >/dev/null 2>&1 || true
docker run -d \
  --name "${PERF_APP_CONTAINER_NAME}" \
  --network "${PERF_NETWORK}" \
  -e DD_TRACE_ENABLED=false \
  -e INCIDENT_SIMULATION_ENABLED=false \
  "${PERF_IMAGE_REF}" >/dev/null

wait_for_app
start_stats_sampler

load_test_status=0

docker run --rm \
  --network "${PERF_NETWORK}" \
  -v "${K6_SCRIPT_PATH}:/scripts/load-test.js:ro" \
  -v "${ARTIFACT_DIR_ABS}:/results" \
  -e BASE_URL="http://${PERF_APP_CONTAINER_NAME}:8080" \
  -e K6_SUMMARY_JSON="/results/k6-summary.json" \
  -e K6_SUMMARY_TEXT="/results/k6-summary.txt" \
  "${K6_IMAGE}" run /scripts/load-test.js || load_test_status=$?

kill "${SAMPLER_PID}" >/dev/null 2>&1 || true
wait "${SAMPLER_PID}" >/dev/null 2>&1 || true
unset SAMPLER_PID

write_profile_summary

if [ "${load_test_status}" -ne 0 ]; then
  echo "k6 exited with status ${load_test_status}" >&2
fi

exit "${load_test_status}"
