#!/usr/bin/env bash
set -euo pipefail
# Requires: buf (1.72.0 tested), protoc (35.1 tested), and protoc-gen-prost
# (install via `cargo install protoc-gen-prost` — it lands in ~/.cargo/bin,
# which is NOT on the default PATH, so `export PATH="$HOME/.cargo/bin:$PATH"`
# before running this script if buf reports the plugin as not found).
cd "$(dirname "${BASH_SOURCE[0]}")"

buf generate

mkdir -p ../service-template/templates/python/generated
protoc --proto_path=proto \
  --python_out=../service-template/templates/python/generated \
  --pyi_out=../service-template/templates/python/generated \
  $(find proto -name '*.proto')
