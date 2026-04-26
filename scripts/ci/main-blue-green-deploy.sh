#!/usr/bin/env bash
set -euo pipefail

: "${DOCKERHUB_REPO:?DOCKERHUB_REPO must be set}"
: "${IMAGE_TAG:?IMAGE_TAG must be set}"
: "${LEGACY_MAIN_CONTAINER_NAME:=springboot-demo}"
: "${PROD_PROXY_NAME:?PROD_PROXY_NAME must be set}"
: "${PROD_NETWORK:?PROD_NETWORK must be set}"
: "${PROD_BLUE_NAME:?PROD_BLUE_NAME must be set}"
: "${PROD_GREEN_NAME:?PROD_GREEN_NAME must be set}"
: "${PROD_PORT:?PROD_PORT must be set}"
: "${STABLE_TAG:?STABLE_TAG must be set}"
: "${SIMULATE_POST_SWITCH_FAILURE:=false}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NGINX_DIR="${REPO_ROOT}/deploy/nginx"
DEFAULT_CONF="${NGINX_DIR}/default.conf"
UPSTREAM_CONF="${NGINX_DIR}/upstream.conf"
CURL_IMAGE="${CURL_IMAGE:-curlimages/curl:8.12.1}"

SWITCHED=0
ACTIVE_SLOT="none"
PREVIOUS_SLOT="none"
CANDIDATE_SLOT="blue"
IMAGE_REF="${DOCKERHUB_REPO}:${IMAGE_TAG}"

log() {
  echo "[main-blue-green] $*"
}

slot_name() {
  case "$1" in
    blue) echo "${PROD_BLUE_NAME}" ;;
    green) echo "${PROD_GREEN_NAME}" ;;
    *)
      echo "Unknown slot: $1" >&2
      exit 1
      ;;
  esac
}

container_running() {
  docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx 'true'
}

wait_for_internal_health() {
  local container_name="$1"
  local timeout_seconds="$2"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if docker run --rm --network "${PROD_NETWORK}" "${CURL_IMAGE}" \
      -fsS "http://${container_name}:8080/actuator/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
}

wait_for_external_health() {
  local timeout_seconds="$1"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if curl -fsS "http://localhost:${PROD_PORT}/actuator/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
}

write_upstream_for_slot() {
  local slot="$1"
  cat > "${UPSTREAM_CONF}" <<EOF
server $(slot_name "${slot}"):8080;
EOF
}

detect_active_slot() {
  if [ -f "${UPSTREAM_CONF}" ] && grep -q "${PROD_BLUE_NAME}:8080" "${UPSTREAM_CONF}" && container_running "${PROD_BLUE_NAME}"; then
    echo "blue"
  elif [ -f "${UPSTREAM_CONF}" ] && grep -q "${PROD_GREEN_NAME}:8080" "${UPSTREAM_CONF}" && container_running "${PROD_GREEN_NAME}"; then
    echo "green"
  else
    echo "none"
  fi
}

ensure_network() {
  if ! docker network inspect "${PROD_NETWORK}" >/dev/null 2>&1; then
    log "Creating Docker network ${PROD_NETWORK}"
    docker network create "${PROD_NETWORK}" >/dev/null
  fi
}

remove_legacy_main_container() {
  if docker inspect "${LEGACY_MAIN_CONTAINER_NAME}" >/dev/null 2>&1; then
    log "Removing legacy main container ${LEGACY_MAIN_CONTAINER_NAME} to free port ${PROD_PORT}"
    docker rm -f "${LEGACY_MAIN_CONTAINER_NAME}" >/dev/null 2>&1 || true
  fi
}

ensure_proxy() {
  if docker inspect "${PROD_PROXY_NAME}" >/dev/null 2>&1; then
    if ! container_running "${PROD_PROXY_NAME}"; then
      log "Starting existing proxy container ${PROD_PROXY_NAME}"
      docker start "${PROD_PROXY_NAME}" >/dev/null
    fi
  else
    log "Creating proxy container ${PROD_PROXY_NAME}"
    docker run -d \
      --name "${PROD_PROXY_NAME}" \
      --network "${PROD_NETWORK}" \
      -p "${PROD_PORT}:8080" \
      -v "${DEFAULT_CONF}:/etc/nginx/conf.d/default.conf:ro" \
      -v "${UPSTREAM_CONF}:/etc/nginx/conf.d/upstream.conf:ro" \
      nginx:1.27-alpine >/dev/null
  fi
}

reload_proxy() {
  if ! docker exec "${PROD_PROXY_NAME}" nginx -s reload >/dev/null 2>&1; then
    log "Reload failed, restarting proxy container"
    docker restart "${PROD_PROXY_NAME}" >/dev/null
  fi
}

run_slot() {
  local slot="$1"
  local container_name

  container_name="$(slot_name "${slot}")"
  docker rm -f "${container_name}" >/dev/null 2>&1 || true
  docker run -d --name "${container_name}" --network "${PROD_NETWORK}" "${IMAGE_REF}" >/dev/null
}

run_stable_fallback() {
  local fallback_slot
  local fallback_name

  fallback_slot="blue"
  if [ "${CANDIDATE_SLOT}" = "blue" ]; then
    fallback_slot="green"
  fi

  fallback_name="$(slot_name "${fallback_slot}")"
  log "Pulling ${DOCKERHUB_REPO}:${STABLE_TAG} for registry-backed recovery"
  docker pull "${DOCKERHUB_REPO}:${STABLE_TAG}" >/dev/null
  docker rm -f "${fallback_name}" >/dev/null 2>&1 || true
  docker run -d --name "${fallback_name}" --network "${PROD_NETWORK}" "${DOCKERHUB_REPO}:${STABLE_TAG}" >/dev/null
  wait_for_internal_health "${fallback_name}" 60
  write_upstream_for_slot "${fallback_slot}"
  ensure_proxy
  reload_proxy
  wait_for_external_health 30
}

on_error() {
  local exit_code=$?

  trap - ERR
  set +e
  log "Deployment failed."

  if [ "${SWITCHED}" -eq 1 ]; then
    log "Traffic already switched. Attempting automatic failover."
    if [ "${PREVIOUS_SLOT}" != "none" ] && wait_for_internal_health "$(slot_name "${PREVIOUS_SLOT}")" 15; then
      log "Failing back to previously healthy ${PREVIOUS_SLOT} slot."
      write_upstream_for_slot "${PREVIOUS_SLOT}"
      ensure_proxy
      reload_proxy
      wait_for_external_health 30 || true
    else
      run_stable_fallback
    fi
  else
    log "Traffic was never switched. Existing production remains unchanged."
  fi

  docker logs --tail 50 "${PROD_PROXY_NAME}" || true
  docker logs --tail 50 "$(slot_name "${CANDIDATE_SLOT}")" || true

  exit "${exit_code}"
}

trap on_error ERR

mkdir -p "${NGINX_DIR}"
ensure_network
remove_legacy_main_container

ACTIVE_SLOT="$(detect_active_slot)"
PREVIOUS_SLOT="${ACTIVE_SLOT}"

if [ "${ACTIVE_SLOT}" = "blue" ]; then
  CANDIDATE_SLOT="green"
else
  CANDIDATE_SLOT="blue"
fi

log "Current active slot: ${ACTIVE_SLOT}"
log "Candidate slot: ${CANDIDATE_SLOT}"

if ! docker image inspect "${IMAGE_REF}" >/dev/null 2>&1; then
  log "Pulling image ${IMAGE_REF}"
  docker pull "${IMAGE_REF}" >/dev/null
fi

log "Deploying ${IMAGE_REF} into ${CANDIDATE_SLOT}"
run_slot "${CANDIDATE_SLOT}"
wait_for_internal_health "$(slot_name "${CANDIDATE_SLOT}")" 60

write_upstream_for_slot "${CANDIDATE_SLOT}"
ensure_proxy
reload_proxy
SWITCHED=1

wait_for_external_health 30

if [ "${SIMULATE_POST_SWITCH_FAILURE}" = "true" ]; then
  log "Simulating post-switch failure before stable tag update."
  exit 1
fi

log "Production switch succeeded. Updating Docker Hub stable tag."
docker tag "${IMAGE_REF}" "${DOCKERHUB_REPO}:${STABLE_TAG}"
docker push "${DOCKERHUB_REPO}:${STABLE_TAG}" >/dev/null

log "Main deployment is healthy on ${CANDIDATE_SLOT}."
