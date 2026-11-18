#!/usr/bin/env bash
# End-to-end check of the Docker setup:
#   1. build and start from scratch (empty volume) → wait until the container is healthy
#   2. docker compose down / up → the database must still be there
#
# Runs as a separate Compose project with its own volume and port, so it never
# touches the data of your normal `docker compose up`. Cleans up after itself.
#
#   scripts/verify-docker.sh            # uses host port 18080
#   VERIFY_PORT=19090 scripts/verify-docker.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export COMPOSE_PROJECT_NAME=currency-converter-verify
export SERVER_PORT="${VERIFY_PORT:-18080}"
HEALTH_URL="http://localhost:${SERVER_PORT}/health"

command -v docker >/dev/null || { echo "docker is not installed"; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker is installed but not running"; exit 1; }

cleanup() { docker compose down -v --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT

wait_healthy() {
    local container last="" status
    container="$(docker compose ps -q server)"
    for _ in $(seq 1 100); do
        status="$(docker inspect --format '{{.State.Health.Status}}' "$container")"
        [ "$status" != "$last" ] && echo "   health: $status" && last="$status"
        [ "$status" = healthy ] && return 0
        [ "$status" = unhealthy ] && { docker compose logs server | tail -20; return 1; }
        sleep 3
    done
    echo "   timed out waiting for healthy"; docker compose logs server | tail -20; return 1
}

health_field() {
    curl -fsS "$HEALTH_URL" | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"
}

echo "1. Fresh start (empty volume)"
cleanup
docker compose up -d --build
wait_healthy
days_before="$(health_field storedDays)"
echo "   /health: $(curl -fsS "$HEALTH_URL")"
docker compose logs server | grep -E "Sync \(startup\)" | sed 's/^/   /'

echo "2. down / up"
docker compose down
docker compose up -d
wait_healthy
days_after="$(health_field storedDays)"
docker compose logs server | grep -E "Sync \(startup\)" | tail -1 | sed 's/^/   /'

if [ "$days_after" -gt 0 ] && [ "$days_before" = "$days_after" ]; then
    echo "OK: healthy from scratch, ${days_after} days of rates survived down/up"
else
    echo "FAIL: stored days before=${days_before} after=${days_after}"
    exit 1
fi
