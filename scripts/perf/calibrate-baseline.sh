#!/usr/bin/env bash
set -euo pipefail

: "${IMAGE_NAME:?IMAGE_NAME must be set}"
: "${IMAGE_TAG:?IMAGE_TAG must be set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

OUTPUT_FILE="${1:-${REPO_ROOT}/performance/baseline.json}"
CALIBRATION_RUNS="${CALIBRATION_RUNS:-3}"
CALIBRATION_DIR="${CALIBRATION_DIR:-${REPO_ROOT}/target/performance/calibration}"

mkdir -p "${CALIBRATION_DIR}"

for run_number in $(seq 1 "${CALIBRATION_RUNS}"); do
  run_dir="${CALIBRATION_DIR}/run-${run_number}"
  mkdir -p "${run_dir}"
  PERF_ARTIFACT_DIR="${run_dir#${REPO_ROOT}/}" IMAGE_NAME="${IMAGE_NAME}" IMAGE_TAG="${IMAGE_TAG}" \
    bash "${SCRIPT_DIR}/run-load-test.sh"
done

python3 - "${OUTPUT_FILE}" "${CALIBRATION_DIR}" <<'PY'
import json
import statistics
import sys
from pathlib import Path

output_path = Path(sys.argv[1])
calibration_dir = Path(sys.argv[2])

p95_values = []
rps_values = []

for summary_file in sorted(calibration_dir.glob("run-*/k6-summary.json")):
    summary = json.loads(summary_file.read_text())
    p95_values.append(float(summary["http_req_duration_p95_ms"]))
    rps_values.append(float(summary["http_reqs_per_second"]))

if not p95_values or not rps_values:
    raise SystemExit("No calibration summaries were found.")

baseline = {
    "http_req_duration_p95_ms": round(statistics.median(p95_values) * 1.25, 2),
    "http_req_failed_rate": 0,
    "http_reqs_per_second_min": round(statistics.median(rps_values) * 0.80, 2),
}

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(baseline, indent=2) + "\n")
PY
