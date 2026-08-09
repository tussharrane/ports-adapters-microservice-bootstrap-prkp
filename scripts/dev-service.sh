#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/dev-service.sh <up|down|watch> [service-name] [host-port]

Builds and runs (or stops) a scaffolded service's own Docker image against
the local Docker Compose network, for iterating on it without touching the
rest of the stack. Requires `pnpm run infra:up` to already be running.

If [service-name] is omitted, the action applies to every service under
services/. When starting more than one service this way, [host-port] (or
the 8080 default) is used as the base port and each subsequent service
gets the next port up.

`watch` builds/runs the service(s) like `up`, then rebuilds and restarts
whichever one changes on disk. Ctrl-C stops watching (containers keep
running).

Examples:
  scripts/dev-service.sh up my-service
  scripts/dev-service.sh up my-service 18080
  scripts/dev-service.sh up
  scripts/dev-service.sh down
  scripts/dev-service.sh watch my-service
  scripts/dev-service.sh watch
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

if [[ ${#ARGS[@]} -lt 1 ]]; then
  usage
  exit 1
fi

ACTION="${ARGS[0]}"
SERVICE_NAME="${ARGS[1]:-}"
HOST_PORT_ARG="${ARGS[2]:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES_ROOT="$REPO_ROOT/services"

WATCH_EXCLUDES=(-not -path '*/.venv/*' -not -path '*/target/*' -not -path '*/__pycache__/*' -not -path '*/.git/*')

resolve_service_names() {
  if [[ -n "$SERVICE_NAME" ]]; then
    echo "$SERVICE_NAME"
    return
  fi
  shopt -s nullglob
  local dirs=("$SERVICES_ROOT"/*/)
  shopt -u nullglob
  if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "Error: no services found under $SERVICES_ROOT. Scaffold one first: scripts/new-service.sh <name> --lang python|rust" >&2
    exit 1
  fi
  for dir in "${dirs[@]}"; do
    basename "$dir"
  done
}

resolve_infra_container() {
  local container
  container="$(docker ps --filter 'label=com.docker.compose.service=postgres' --filter 'status=running' --format '{{.ID}}' | head -n1)"
  if [[ -z "$container" ]]; then
    echo "Error: infra 'postgres' container not found/running. Run 'pnpm run infra:up' first." >&2
    exit 1
  fi
  echo "$container"
}

resolve_infra_network() {
  local network
  network="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$1" | awk '{print $1}')"
  if [[ -z "$network" ]]; then
    echo "Error: could not resolve infra network from postgres container." >&2
    exit 1
  fi
  echo "$network"
}

resolve_infra_label() {
  local value
  value="$(docker inspect -f "{{index .Config.Labels \"$2\"}}" "$1")"
  if [[ -z "$value" ]]; then
    echo "Error: could not resolve $2 from postgres container." >&2
    exit 1
  fi
  echo "$value"
}

service_up() {
  local name="$1" port="$2"
  local dir="$SERVICES_ROOT/$name"

  if [[ ! -d "$dir" ]]; then
    echo "Error: $dir does not exist. Scaffold it first: scripts/new-service.sh $name --lang python|rust" >&2
    exit 1
  fi

  local infra_container network project config_files working_dir
  infra_container="$(resolve_infra_container)"
  network="$(resolve_infra_network "$infra_container")"
  project="$(resolve_infra_label "$infra_container" com.docker.compose.project)"
  config_files="$(resolve_infra_label "$infra_container" com.docker.compose.project.config_files)"
  working_dir="$(resolve_infra_label "$infra_container" com.docker.compose.project.working_dir)"

  docker rm -f "$name" >/dev/null 2>&1 || true
  docker build -t "$name" "$dir"
  docker run -d --name "$name" --network "$network" \
    --label "com.docker.compose.project=$project" \
    --label "com.docker.compose.service=$name" \
    --label "com.docker.compose.project.config_files=$config_files" \
    --label "com.docker.compose.project.working_dir=$working_dir" \
    --label "com.docker.compose.oneoff=False" \
    --label "com.docker.compose.container-number=1" \
    -e DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@postgres:5432/$POSTGRES_DB?sslmode=disable" \
    -e KAFKA_BROKERS=kafka:9092 \
    -e HEALTH_HOST=0.0.0.0 -e HEALTH_PORT=8080 \
    -p "$port:8080" \
    "$name"
  echo "Started $name — curl http://localhost:$port"
}

service_down() {
  local name="$1"
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker rmi "$name" >/dev/null 2>&1 || true
  echo "Stopped and removed $name"
}

watch_service() {
  local name="$1" port="$2"
  local dir="$SERVICES_ROOT/$name"
  local marker
  marker="$(mktemp)"

  service_up "$name" "$port"
  touch "$marker"
  echo "Watching $dir for changes..."

  while true; do
    sleep 2
    local changed
    changed="$(find "$dir" -type f "${WATCH_EXCLUDES[@]}" -newer "$marker" -print -quit)"
    if [[ -n "$changed" ]]; then
      echo "Change detected in $name ($changed) — rebuilding..."
      service_up "$name" "$port"
      touch "$marker"
    fi
  done
}

load_env() {
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
}

case "$ACTION" in
  up)
    load_env
    BASE_PORT="${HOST_PORT_ARG:-8080}"
    i=0
    while IFS= read -r name; do
      service_up "$name" "$((BASE_PORT + i))"
      i=$((i + 1))
    done < <(resolve_service_names)
    ;;
  down)
    while IFS= read -r name; do
      service_down "$name"
    done < <(resolve_service_names)
    ;;
  watch)
    load_env
    BASE_PORT="${HOST_PORT_ARG:-8080}"
    NAMES=()
    while IFS= read -r name; do
      NAMES+=("$name")
    done < <(resolve_service_names)

    if [[ ${#NAMES[@]} -eq 1 ]]; then
      watch_service "${NAMES[0]}" "$BASE_PORT"
    else
      PIDS=()
      cleanup() {
        echo "Stopping watch..."
        for pid in "${PIDS[@]}"; do
          kill "$pid" >/dev/null 2>&1 || true
        done
        exit 0
      }
      trap cleanup INT TERM

      i=0
      for name in "${NAMES[@]}"; do
        watch_service "$name" "$((BASE_PORT + i))" &
        PIDS+=("$!")
        i=$((i + 1))
      done
      wait
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
