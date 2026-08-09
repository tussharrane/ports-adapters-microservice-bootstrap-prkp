#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/dev-service.sh <up|down> <service-name> [host-port]

Builds and runs (or stops) a scaffolded service's own Docker image against
the local Docker Compose network, for iterating on it without touching the
rest of the stack. Requires `pnpm run infra:up` to already be running.

Examples:
  scripts/dev-service.sh up my-service
  scripts/dev-service.sh up my-service 18080
  scripts/dev-service.sh down my-service
EOF
}

# pnpm forwards `pnpm run service:up -- my-service` as a literal `--` token
# mixed in with the real arguments (its position depends on how much text is
# already in the package.json script) — filter it out rather than assume
# where it lands.
ARGS=()
for arg in "$@"; do
  [[ "$arg" == "--" ]] && continue
  ARGS+=("$arg")
done

if [[ ${#ARGS[@]} -lt 2 ]]; then
  usage
  exit 1
fi

ACTION="${ARGS[0]}"
SERVICE_NAME="${ARGS[1]}"
HOST_PORT="${ARGS[2]:-8080}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_DIR="$REPO_ROOT/services/$SERVICE_NAME"

case "$ACTION" in
  up)
    if [[ ! -d "$SERVICE_DIR" ]]; then
      echo "Error: $SERVICE_DIR does not exist. Scaffold it first: scripts/new-service.sh $SERVICE_NAME --lang python|rust" >&2
      exit 1
    fi

    if [[ -f "$REPO_ROOT/.env" ]]; then
      set -a
      # shellcheck disable=SC1091
      source "$REPO_ROOT/.env"
      set +a
    fi

    POSTGRES_USER="${POSTGRES_USER:-app}"
    POSTGRES_DB="${POSTGRES_DB:-bootstrap}"

    if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then
      echo "Error: POSTGRES_PASSWORD not set. Run 'cp .env.example .env' first (or export it)." >&2
      exit 1
    fi

    docker rm -f "$SERVICE_NAME" >/dev/null 2>&1 || true
    docker build -t "$SERVICE_NAME" "$SERVICE_DIR"
    docker run -d --name "$SERVICE_NAME" --network ports-adapters-microservice-bootstrap_default \
      -e DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@postgres:5432/$POSTGRES_DB?sslmode=disable" \
      -e KAFKA_BROKERS=kafka:9092 \
      -e HEALTH_HOST=0.0.0.0 -e HEALTH_PORT=8080 \
      -p "$HOST_PORT:8080" \
      "$SERVICE_NAME"
    echo "Started $SERVICE_NAME — curl http://localhost:$HOST_PORT"
    ;;
  down)
    docker rm -f "$SERVICE_NAME" >/dev/null 2>&1 || true
    docker rmi "$SERVICE_NAME" >/dev/null 2>&1 || true
    echo "Stopped and removed $SERVICE_NAME"
    ;;
  *)
    usage
    exit 1
    ;;
esac
