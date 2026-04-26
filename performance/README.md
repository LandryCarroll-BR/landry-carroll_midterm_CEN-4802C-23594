# Lightweight Performance Gate

This repo runs a lightweight `k6` load test in Jenkins for every code-change build.

## Files

- Baseline thresholds: [performance/baseline.json](/Users/landry_local/Documents/School/CEN-4802C-23594/landry-carroll_midterm_CEN-4802C-23594/performance/baseline.json)
- Load scenario: [scripts/perf/load-test.js](/Users/landry_local/Documents/School/CEN-4802C-23594/landry-carroll_midterm_CEN-4802C-23594/scripts/perf/load-test.js)
- Runner: [scripts/perf/run-load-test.sh](/Users/landry_local/Documents/School/CEN-4802C-23594/landry-carroll_midterm_CEN-4802C-23594/scripts/perf/run-load-test.sh)
- Baseline evaluation: [scripts/perf/evaluate-baseline.sh](/Users/landry_local/Documents/School/CEN-4802C-23594/landry-carroll_midterm_CEN-4802C-23594/scripts/perf/evaluate-baseline.sh)
- Datadog publishing: [scripts/perf/publish-datadog-metrics.sh](/Users/landry_local/Documents/School/CEN-4802C-23594/landry-carroll_midterm_CEN-4802C-23594/scripts/perf/publish-datadog-metrics.sh)
- Calibration helper: [scripts/perf/calibrate-baseline.sh](/Users/landry_local/Documents/School/CEN-4802C-23594/landry-carroll_midterm_CEN-4802C-23594/scripts/perf/calibrate-baseline.sh)

## Metrics

The CI gate currently enforces:

- `http_req_duration_p95_ms`
- `http_req_failed_rate`
- `http_reqs_per_second_min`

It also captures but does not gate on:

- `container_cpu_percent_max`
- `container_memory_mb_max`

## Refreshing the Baseline

1. Build the local image:
   - `docker build -t springboot-demo:$(git rev-parse --short HEAD) .`
2. Run calibration:
   - `IMAGE_NAME=springboot-demo IMAGE_TAG=$(git rev-parse --short HEAD) scripts/perf/calibrate-baseline.sh`
3. Review and commit the updated [performance/baseline.json](/Users/landry_local/Documents/School/CEN-4802C-23594/landry-carroll_midterm_CEN-4802C-23594/performance/baseline.json).

The calibration helper runs the load test three times and writes new thresholds with built-in headroom:

- p95 latency threshold = median p95 * 1.25
- minimum RPS threshold = median RPS * 0.80
- error rate threshold = `0`
