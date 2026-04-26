#!/usr/bin/env bash
set -euo pipefail

PERF_BASELINE_FILE="${PERF_BASELINE_FILE:-performance/baseline.json}"
PERF_ARTIFACT_DIR="${PERF_ARTIFACT_DIR:-target/performance}"
PERF_SUMMARY_JSON="${PERF_SUMMARY_JSON:-${PERF_ARTIFACT_DIR}/k6-summary.json}"
PERF_THRESHOLD_REPORT="${PERF_THRESHOLD_REPORT:-${PERF_ARTIFACT_DIR}/threshold-report.txt}"
PERF_EVALUATION_JSON="${PERF_EVALUATION_JSON:-${PERF_ARTIFACT_DIR}/evaluation.json}"

python3 - "${PERF_BASELINE_FILE}" "${PERF_SUMMARY_JSON}" "${PERF_THRESHOLD_REPORT}" "${PERF_EVALUATION_JSON}" <<'PY'
import json
import sys
from pathlib import Path

baseline_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
report_path = Path(sys.argv[3])
evaluation_path = Path(sys.argv[4])

baseline = json.loads(baseline_path.read_text())
summary = json.loads(summary_path.read_text())

checks = [
    {
        "name": "http_req_duration_p95_ms",
        "actual": float(summary["http_req_duration_p95_ms"]),
        "threshold": float(baseline["http_req_duration_p95_ms"]),
        "operator": "<=",
        "pass": float(summary["http_req_duration_p95_ms"]) <= float(baseline["http_req_duration_p95_ms"]),
        "unit": "ms",
    },
    {
        "name": "http_req_failed_rate",
        "actual": float(summary["http_req_failed_rate"]),
        "threshold": float(baseline["http_req_failed_rate"]),
        "operator": "<=",
        "pass": float(summary["http_req_failed_rate"]) <= float(baseline["http_req_failed_rate"]),
        "unit": "ratio",
    },
    {
        "name": "http_reqs_per_second",
        "actual": float(summary["http_reqs_per_second"]),
        "threshold": float(baseline["http_reqs_per_second_min"]),
        "operator": ">=",
        "pass": float(summary["http_reqs_per_second"]) >= float(baseline["http_reqs_per_second_min"]),
        "unit": "req/s",
    },
]

overall_pass = all(check["pass"] for check in checks)

evaluation = {
    "threshold_pass": 1 if overall_pass else 0,
    "baseline": baseline,
    "summary": summary,
    "checks": checks,
}

report_lines = ["Lightweight performance gate report", ""]
for check in checks:
    status = "PASS" if check["pass"] else "FAIL"
    report_lines.append(
        f"{check['name']}: actual={check['actual']:.2f} {check['unit']} "
        f"{check['operator']} threshold={check['threshold']:.2f} {check['unit']} -> {status}"
    )

report_lines.append("")
report_lines.append(f"overall={'PASS' if overall_pass else 'FAIL'}")

report_path.write_text("\n".join(report_lines) + "\n")
evaluation_path.write_text(json.dumps(evaluation, indent=2) + "\n")

sys.exit(0 if overall_pass else 1)
PY
