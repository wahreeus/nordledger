#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
PACKAGE_DIR="$BUILD_DIR/package"
ZIP_PATH="$BUILD_DIR/nordledger_lambda.zip"

mkdir -p "$BUILD_DIR"
rm -rf "$PACKAGE_DIR" "$ZIP_PATH"
mkdir -p "$PACKAGE_DIR"

build_with_docker() {
  docker run --rm \
    -v "$ROOT_DIR":/var/task \
    -w /var/task \
    public.ecr.aws/lambda/python:3.11 \
    sh -lc '
      python -m pip install --upgrade pip >/dev/null
      python -m pip install --no-cache-dir -r lambda/requirements.txt -t build/package >/dev/null
      cp lambda/*.py build/package/
      python - <<"PY"
import os
import zipfile

root = "build/package"
outfile = "build/nordledger_lambda.zip"

with zipfile.ZipFile(outfile, "w", zipfile.ZIP_DEFLATED) as zf:
    for folder, _, files in os.walk(root):
        for name in files:
            path = os.path.join(folder, name)
            arcname = os.path.relpath(path, root)
            zf.write(path, arcname)
PY
    '
}

build_locally() {
  python3 -m pip install --upgrade pip >/dev/null
  python3 -m pip install --no-cache-dir -r "$ROOT_DIR/lambda/requirements.txt" -t "$PACKAGE_DIR" >/dev/null
  cp "$ROOT_DIR"/lambda/*.py "$PACKAGE_DIR"/
  python3 - <<PY
import os
import zipfile

root = ${PACKAGE_DIR@Q}
outfile = ${ZIP_PATH@Q}

with zipfile.ZipFile(outfile, "w", zipfile.ZIP_DEFLATED) as zf:
    for folder, _, files in os.walk(root):
        for name in files:
            path = os.path.join(folder, name)
            arcname = os.path.relpath(path, root)
            zf.write(path, arcname)
PY
}

if command -v docker >/dev/null 2>&1; then
  echo "Building Lambda package with Docker..."
  build_with_docker
else
  echo "Docker not found. Falling back to local Python packaging."
  echo "Note: on macOS this may produce dependencies incompatible with AWS Lambda Linux runtime."
  build_locally
fi

echo "Created $ZIP_PATH"
