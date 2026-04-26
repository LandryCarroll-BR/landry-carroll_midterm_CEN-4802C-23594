import http from 'k6/http';
import { check, sleep } from 'k6';

const baseUrl = __ENV.BASE_URL || 'http://app-under-test:8080';
const summaryJsonPath = __ENV.K6_SUMMARY_JSON || '/results/k6-summary.json';
const summaryTextPath = __ENV.K6_SUMMARY_TEXT || '/results/k6-summary.txt';

const routes = [
  { name: 'home', path: '/' },
  { name: 'greeting', path: '/greeting?name=perf' },
  { name: 'goodbye', path: '/goodbye?name=perf' },
  { name: 'health', path: '/actuator/health' },
];

export const options = {
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
  scenarios: {
    lightweight_ci: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '5s', target: 2 },
        { duration: '20s', target: 5 },
        { duration: '5s', target: 0 },
      ],
      gracefulRampDown: '0s',
    },
  },
};

function metricValue(data, metricName, valueName, fallback = 0) {
  const metric = data.metrics[metricName];
  if (!metric || !metric.values || metric.values[valueName] === undefined) {
    return fallback;
  }

  return Number(metric.values[valueName]);
}

function buildSummary(data) {
  return {
    base_url: baseUrl,
    http_req_duration_p95_ms: Number(metricValue(data, 'http_req_duration', 'p(95)').toFixed(2)),
    http_req_duration_avg_ms: Number(metricValue(data, 'http_req_duration', 'avg').toFixed(2)),
    http_req_failed_rate: Number(metricValue(data, 'http_req_failed', 'rate').toFixed(6)),
    http_reqs_per_second: Number(metricValue(data, 'http_reqs', 'rate').toFixed(2)),
    checks_pass_rate: Number(metricValue(data, 'checks', 'rate').toFixed(6)),
    iterations: Number(metricValue(data, 'iterations', 'count')),
  };
}

function formatSummary(summary) {
  return [
    'k6 lightweight CI performance summary',
    `base_url=${summary.base_url}`,
    `http_req_duration_p95_ms=${summary.http_req_duration_p95_ms}`,
    `http_req_duration_avg_ms=${summary.http_req_duration_avg_ms}`,
    `http_req_failed_rate=${summary.http_req_failed_rate}`,
    `http_reqs_per_second=${summary.http_reqs_per_second}`,
    `checks_pass_rate=${summary.checks_pass_rate}`,
    `iterations=${summary.iterations}`,
    '',
  ].join('\n');
}

export default function () {
  const route = routes[__ITER % routes.length];
  const response = http.get(`${baseUrl}${route.path}`, {
    tags: { endpoint: route.name },
  });

  check(response, {
    'status is 200': (res) => res.status === 200,
  });

  sleep(0.2);
}

export function handleSummary(data) {
  const summary = buildSummary(data);

  return {
    [summaryJsonPath]: JSON.stringify(summary, null, 2),
    [summaryTextPath]: formatSummary(summary),
  };
}
