# Datadog Setup

This repo provisions the Datadog Agent from Jenkins before `staging` and `main` deployments.

## Jenkins

- Create a Secret Text credential with ID `DATADOG_API_KEY`.
- Create a Secret Text credential with ID `DD_SITE`.
  Set it to your Datadog site value, for example `datadoghq.com`, `datadoghq.eu`, or `us3.datadoghq.com`.

## What Jenkins Boots

- Script: [scripts/ci/ensure-datadog-agent.sh](/Users/landry_local/Documents/School/CEN-4802C-23594/landry-carroll_midterm_CEN-4802C-23594/scripts/ci/ensure-datadog-agent.sh)
- HTTP check config: [deploy/datadog/http_check.d/conf.yaml](/Users/landry_local/Documents/School/CEN-4802C-23594/landry-carroll_midterm_CEN-4802C-23594/deploy/datadog/http_check.d/conf.yaml)

The Agent collects:

- Docker container metrics and live container metadata
- Container stdout/stderr logs for containers with Datadog log labels
- Application traces from Java containers on the shared Docker network
- A production health check against `http://springboot-demo-main-proxy:8080/actuator/health`

## Datadog UI

Create these assets in Datadog after the first successful deployment:

- Service check monitor:
  - Check: `http.can_connect`
  - Filter: `name:springboot-demo-prod-health env:prod service:springboot-demo`
  - Alert when the check fails for 2 consecutive runs
  - Notify by email
- Saved Log Explorer views:
  - `service:springboot-demo env:prod`
  - `service:springboot-demo env:staging`
  - `service:springboot-demo-proxy env:prod`

- Metric monitors for CI performance regressions on `main`:
  - Use the current values from [performance/baseline.json](/Users/landry_local/Documents/School/CEN-4802C-23594/landry-carroll_midterm_CEN-4802C-23594/performance/baseline.json) when creating these monitors.
  - `max(last_15m):max:ci.performance.http_req_duration_p95_ms{service:springboot-demo,env:ci,branch:main} > 7.46`
  - `max(last_15m):max:ci.performance.http_req_failed_rate{service:springboot-demo,env:ci,branch:main} > 0`
  - `min(last_15m):min:ci.performance.http_reqs_per_second{service:springboot-demo,env:ci,branch:main} < 10.42`
  - Route these monitors to the same notification destination already used for your crash and availability alerts.

## APM

APM is enabled in the app image and activated in deployed containers with these runtime settings:

- `DD_TRACE_ENABLED=true`
- `DD_AGENT_HOST=springboot-demo-datadog-agent`
- `DD_TRACE_AGENT_PORT=8126`
- `DD_SERVICE=springboot-demo`
- `DD_ENV=staging|prod`
- `DD_VERSION=<git-sha or stable>`
- `DD_LOGS_INJECTION=true`

Verification steps in Datadog:

- Open `APM -> Services` and look for `springboot-demo`
- Filter by `env:staging` or `env:prod`
- Open one service and confirm traces appear for the HTTP endpoints in this app
- In Log Explorer, open one app log line and confirm it links to a trace after traffic has hit the service

For incident review, add `version:<git-sha>` to the query so app and proxy logs line up with the deployed image tag.

## Crash Simulation

- Jenkins now exposes a boolean parameter named `ENABLE_INCIDENT_SIMULATION`.
- When it is `true`, deployed app containers expose:
  - `POST /simulate/error` to generate a logged 500 error
  - `POST /simulate/crash` to halt the JVM after a short delay
- When it is `false`, both endpoints return `404`.

Use this to trigger Datadog alerts without introducing compile-time or startup failures into the build itself.
