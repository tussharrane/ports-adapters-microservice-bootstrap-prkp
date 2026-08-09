#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/new-service.sh <service-name> --lang python|rust

Scaffolds a new service under services/<service-name> from the matching
packages/service-template/templates/<lang> skeleton.

Examples:
  scripts/new-service.sh risk-execution-service --lang rust
  pnpm run new-service -- risk-execution-service --lang python
EOF
}

if [[ $# -lt 3 ]]; then
  usage
  exit 1
fi

SERVICE_NAME="$1"
shift

LANG_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang)
      LANG_ARG="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$LANG_ARG" ]]; then
  echo "Error: --lang is required" >&2
  usage
  exit 1
fi

if [[ ! "$SERVICE_NAME" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]]; then
  echo "Error: service name must be kebab-case (e.g. risk-execution-service), got: $SERVICE_NAME" >&2
  exit 1
fi

case "$LANG_ARG" in
  python) TEMPLATE_DIR="python" ;;
  rust) TEMPLATE_DIR="rust" ;;
  *)
    echo "Error: unknown --lang '$LANG_ARG' (must be python|rust)" >&2
    exit 1
    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/packages/service-template/templates/$TEMPLATE_DIR"
DEST="$REPO_ROOT/services/$SERVICE_NAME"

if [[ ! -d "$SRC" ]]; then
  echo "Error: template not found at $SRC" >&2
  exit 1
fi

if [[ -e "$DEST" ]]; then
  echo "Error: $DEST already exists, refusing to overwrite" >&2
  exit 1
fi

mkdir -p "$REPO_ROOT/services"
# `cp -R` doesn't respect .gitignore — it would copy whatever build
# artifacts (.venv/, target/, __pycache__/, .ruff_cache/) happen to exist
# in the template on disk at scaffold time, not just its tracked source.
rsync -a --exclude='.venv' --exclude='target' --exclude='__pycache__' --exclude='.ruff_cache' "$SRC/" "$DEST/"
trap 'rm -rf "$DEST"' ERR

SERVICE_NAME_PASCAL="$(echo "$SERVICE_NAME" | awk -F- '{ for (i=1;i<=NF;i++) { $i=toupper(substr($i,1,1)) substr($i,2) }; print }' OFS='')"
SERVICE_NAME_SNAKE="${SERVICE_NAME//-/_}"

find "$DEST" -type f -print0 | while IFS= read -r -d '' file; do
  grep -Iq . "$file" || continue
  sed -i.bak \
    -e "s/__SERVICE_NAME__/${SERVICE_NAME}/g" \
    -e "s/__ServiceName__/${SERVICE_NAME_PASCAL}/g" \
    -e "s/__service_name__/${SERVICE_NAME_SNAKE}/g" \
    "$file"
  rm -f "$file.bak"
done

if [[ "$LANG_ARG" == "python" ]]; then
  echo "Registering services/$SERVICE_NAME with the root pyrightconfig.json..."
  python3 -c "
import json
import pathlib

config_path = pathlib.Path('$REPO_ROOT/pyrightconfig.json')
config = json.loads(config_path.read_text()) if config_path.exists() else {}
envs = config.setdefault('executionEnvironments', [])
root = 'services/$SERVICE_NAME'
envs[:] = [e for e in envs if e.get('root') != root]
envs.append({
    'root': root,
    'extraPaths': [f'{root}/src', f'{root}/src/adapters/in', f'{root}/src/ports/in', f'{root}/generated'],
})
config_path.write_text(json.dumps(config, indent=2) + '\n')
"
fi

trap - ERR
echo "Created services/$SERVICE_NAME ($LANG_ARG)"
echo
case "$LANG_ARG" in
  python)
    echo "Next steps:"
    echo "  pnpm run build"
    echo "  cd services/$SERVICE_NAME"
    echo "  .venv/bin/python3 main.py"
    echo "(VS Code: reload window to pick up this service's import paths via the root pyrightconfig.json)"
    ;;
  rust)
    echo "Next steps:"
    echo "  cd services/$SERVICE_NAME"
    echo "  cargo run"
    ;;
esac
