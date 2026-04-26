#!/usr/bin/env bash
set -euo pipefail

: "${DATADOG_API_KEY:?DATADOG_API_KEY must be set}"
: "${DD_SITE:?DD_SITE must be set}"

PERF_ARTIFACT_DIR="${PERF_ARTIFACT_DIR:-target/performance}"
PERF_SUMMARY_JSON="${PERF_SUMMARY_JSON:-${PERF_ARTIFACT_DIR}/k6-summary.json}"
PERF_PROFILE_JSON="${PERF_PROFILE_JSON:-${PERF_ARTIFACT_DIR}/profile.json}"
PERF_EVALUATION_JSON="${PERF_EVALUATION_JSON:-${PERF_ARTIFACT_DIR}/evaluation.json}"
PERF_PAYLOAD_JSON="${PERF_PAYLOAD_JSON:-${PERF_ARTIFACT_DIR}/datadog-metrics-payload.json}"
PERF_BRANCH_NAME="${PERF_BRANCH_NAME:-${NORMALIZED_BRANCH:-${BRANCH_NAME:-unknown}}}"
PERF_GIT_SHA="${PERF_GIT_SHA:-${IMAGE_TAG:-unknown}}"
PERF_BUILD_NUMBER="${PERF_BUILD_NUMBER:-${BUILD_NUMBER:-local}}"
PERF_SERVICE="${PERF_SERVICE:-springboot-demo}"

case "${DD_SITE}" in
  api.*)
    DATADOG_API_BASE="https://${DD_SITE}"
    ;;
  *)
    DATADOG_API_BASE="https://api.${DD_SITE}"
    ;;
esac

python3 - "${PERF_SUMMARY_JSON}" "${PERF_PROFILE_JSON}" "${PERF_EVALUATION_JSON}" "${PERF_PAYLOAD_JSON}" "${PERF_SERVICE}" "${PERF_BRANCH_NAME}" "${PERF_GIT_SHA}" "${PERF_BUILD_NUMBER}" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text())
profile = json.loads(Path(sys.argv[2]).read_text())
evaluation = json.loads(Path(sys.argv[3]).read_text())
payload_path = Path(sys.argv[4])
service = sys.argv[5]
branch = sys.argv[6]
git_sha = sys.argv[7]
build_number = sys.argv[8]

timestamp = int(datetime.now(timezone.utc).timestamp())
tags = [
    f"service:{service}",
    "env:ci",
    f"branch:{branch}",
    f"git_sha:{git_sha}",
    "pipeline:jenkins",
    f"build_number:{build_number}",
]

series = []
for metric_name, value in [
    ("ci.performance.http_req_duration_p95_ms", summary["http_req_duration_p95_ms"]),
    ("ci.performance.http_req_failed_rate", summary["http_req_failed_rate"]),
    ("ci.performance.http_reqs_per_second", summary["http_reqs_per_second"]),
    ("ci.performance.container_cpu_percent_max", profile["container_cpu_percent_max"]),
    ("ci.performance.container_memory_mb_max", profile["container_memory_mb_max"]),
    ("ci.performance.threshold_pass", evaluation["threshold_pass"]),
]:
    series.append(
        {
            "metric": metric_name,
            "points": [[timestamp, float(value)]],
            "type": "gauge",
            "tags": tags,
        }
    )

payload_path.write_text(json.dumps({"series": series}, indent=2) + "\n")
PY

curl -fsS \
  -H "Content-Type: application/json" \
  -H "DD-API-KEY: ${DATADOG_API_KEY}" \
  -X POST \
  "${DATADOG_API_BASE}/api/v1/series" \
  -d @"${PERF_PAYLOAD_JSON}" >/dev/null
