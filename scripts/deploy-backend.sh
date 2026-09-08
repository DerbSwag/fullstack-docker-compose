#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="$REPO_ROOT/.env"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"

IMAGE_PREFIX="ghcr.io/derbswag/fullstack-backend"
CONTAINER_NAME="fullstack-backend"

MAX_ATTEMPTS=18
SLEEP_SECONDS=5

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

wait_for_health() {
    local attempt
    local status

    for ((attempt=1; attempt<=MAX_ATTEMPTS; attempt++)); do
        status="$(
            docker inspect \
                --format='{{.State.Health.Status}}' \
                "$CONTAINER_NAME" 2>/dev/null || true
        )"

        echo "Attempt $attempt/$MAX_ATTEMPTS: ${status:-unknown}"

        if [ "$status" = "healthy" ]; then
            return 0
        fi

        if [ "$status" = "unhealthy" ]; then
            return 1
        fi

        sleep "$SLEEP_SECONDS"
    done

    return 1
}

set_backend_image() {
    local image="$1"

    grep -q '^BACKEND_IMAGE=' "$ENV_FILE" \
        || fail "BACKEND_IMAGE not found in $ENV_FILE"

    sed -i \
        "s|^BACKEND_IMAGE=.*|BACKEND_IMAGE=$image|" \
        "$ENV_FILE"
}

rollback() {
    echo
    echo "===== ROLLBACK ====="
    echo "rollback image: $OLD_IMAGE"

    set_backend_image "$OLD_IMAGE"

    cd "$REPO_ROOT"
    docker compose up -d --no-deps backend

    echo
    echo "===== WAIT FOR ROLLBACK HEALTH ====="

    if wait_for_health; then
        echo "rollback health: OK"
        echo "rollback: SUCCESS"
    else
        echo "rollback health: FAILED" >&2
        docker compose ps >&2 || true
        docker compose logs backend >&2 || true
        fail "deployment failed and rollback did not become healthy"
    fi

    fail "deployment failed and was rolled back"
}

echo "===== BACKEND DEPLOY SAFETY CHECK ====="

[ "$#" -eq 1 ] \
    || fail "usage: $0 <40-character-git-sha>"

SHA="$1"

[[ "$SHA" =~ ^[0-9a-fA-F]{40}$ ]] \
    || fail "invalid Git SHA: $SHA"

command -v docker >/dev/null 2>&1 \
    || fail "docker command not found"

[ -f "$ENV_FILE" ] \
    || fail ".env not found: $ENV_FILE"

[ -f "$COMPOSE_FILE" ] \
    || fail "docker-compose.yml not found"

docker compose version >/dev/null 2>&1 \
    || fail "docker compose is not available"

docker inspect "$CONTAINER_NAME" >/dev/null 2>&1 \
    || fail "backend container not found: $CONTAINER_NAME"

NEW_IMAGE="${IMAGE_PREFIX}:${SHA}"

OLD_IMAGE="$(
    docker inspect "$CONTAINER_NAME" \
        --format='{{.Config.Image}}'
)"

echo "repo root: $REPO_ROOT"
echo "old image: $OLD_IMAGE"
echo "new image: $NEW_IMAGE"

if [ "$OLD_IMAGE" = "$NEW_IMAGE" ]; then
    echo
    echo "Backend is already running requested image."

    curl -fsS http://127.0.0.1:3001/health >/dev/null \
        || fail "current backend health check failed"

    echo "health: OK"
    echo "deployment: NO CHANGE"
    exit 0
fi

echo
echo "===== PULL TARGET IMAGE ====="

docker pull "$NEW_IMAGE"

docker image inspect "$NEW_IMAGE" >/dev/null 2>&1 \
    || fail "target image not found after pull"

echo
echo "===== VALIDATE COMPOSE ====="

cd "$REPO_ROOT"

BACKEND_IMAGE="$NEW_IMAGE" docker compose config >/dev/null

echo "compose validation: OK"

echo
echo "===== UPDATE BACKEND IMAGE ====="

set_backend_image "$NEW_IMAGE"

echo "BACKEND_IMAGE updated."

echo
echo "===== RECREATE BACKEND ONLY ====="

if ! docker compose up -d --no-deps backend; then
    rollback
fi

echo
echo "===== WAIT FOR BACKEND HEALTH ====="

if ! wait_for_health; then
    echo "backend failed Docker health check"
    docker compose ps || true
    docker compose logs backend || true
    rollback
fi

echo
echo "===== POST-DEPLOY VALIDATION ====="

if ! curl -fsS http://127.0.0.1:3001/health >/dev/null; then
    echo "direct health endpoint failed"
    rollback
fi

if ! curl -fsS http://127.0.0.1:3001/users >/dev/null; then
    echo "users API failed"
    rollback
fi

if ! curl -fsS http://127.0.0.1/api/health >/dev/null; then
    echo "nginx API health check failed"
    rollback
fi

echo "direct health: OK"
echo "users API:     OK"
echo "nginx health:  OK"

echo
echo "===== DEPLOYMENT COMPLETE ====="

docker inspect "$CONTAINER_NAME" \
    --format='ConfigImage={{.Config.Image}} ImageID={{.Image}} Health={{.State.Health.Status}}'

echo
echo "previous image: $OLD_IMAGE"
echo "current image:  $NEW_IMAGE"
echo "deployment: SUCCESS"
