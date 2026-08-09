#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build.sh

Regenerates packages/contracts, sets up every Python service's virtualenv,
then builds a Docker image for every real service under services/.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Phase 1: toolchain preflight + contracts regen ---

check_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x "$HOME/.cargo/bin/$tool" ]]; then
    return 0
  fi
  echo "Error: '$tool' not found on PATH or in \$HOME/.cargo/bin." >&2
  echo "See README.md Prerequisites for install instructions." >&2
  exit 1
}

echo "Regenerating contracts..."

check_tool buf
check_tool protoc
check_tool protoc-gen-prost

export PATH="$HOME/.cargo/bin:$PATH"
"$REPO_ROOT/packages/contracts/generate.sh"

# --- Phase 2: set up every Python service's virtualenv ---

echo "Setting up Python service virtualenvs..."

shopt -s nullglob
PYPROJECTS=("$REPO_ROOT"/services/*/pyproject.toml)
shopt -u nullglob

if [[ ${#PYPROJECTS[@]} -eq 0 ]]; then
  echo "No Python services to set up."
else
  for pyproject in "${PYPROJECTS[@]}"; do
    service_dir="$(dirname "$pyproject")"
    echo "Creating venv and installing dependencies for $(basename "$service_dir")..."
    python3 -m venv --clear "$service_dir/.venv"
    PY_DEPS=()
    while IFS= read -r dep; do
      PY_DEPS+=("$dep")
    done < <("$service_dir/.venv/bin/python3" -c "import tomllib; data=tomllib.load(open('$pyproject', 'rb')); deps=data['project']['dependencies']; opt=data['project'].get('optional-dependencies', {}); deps+=opt.get('lint', []); deps+=opt.get('typecheck', []); print('\n'.join(deps))")
    "$service_dir/.venv/bin/pip" install -q "${PY_DEPS[@]}"
  done
fi

# --- Phase 3: build every real service ---

echo "Building services..."

shopt -s nullglob
SERVICE_DIRS=("$REPO_ROOT"/services/*/)
shopt -u nullglob

if [[ ${#SERVICE_DIRS[@]} -eq 0 ]]; then
  echo "No services to build."
  exit 0
fi

for dir in "${SERVICE_DIRS[@]}"; do
  name="$(basename "$dir")"
  echo "Building $name..."
  docker build -t "$name" "$dir"
done

echo "Build complete."
