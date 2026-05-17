#!/usr/bin/env bash
# build_layer.sh <backend_root> <build_dir>
#
# Installs Python dependencies for the Lambda layer into <build_dir>/layer/python,
# then zips the result to <build_dir>/lambda_layer.zip.
#
# Called by Terraform's null_resource.build_lambda_layer.
# Requirements: Python 3.12+, pip, zip

set -euo pipefail

BACKEND_ROOT="${1:?Usage: build_layer.sh <backend_root> <build_dir>}"
BUILD_DIR="${2:?Usage: build_layer.sh <backend_root> <build_dir>}"
LAYER_DIR="${BUILD_DIR}/layer"
PYTHON_SITE="${LAYER_DIR}/python"

echo "==> Building Lambda layer"
echo "    requirements: ${BACKEND_ROOT}/requirements.txt"
echo "    output:       ${BUILD_DIR}/lambda_layer.zip"

# Clean prior build
rm -rf "${LAYER_DIR}"
mkdir -p "${PYTHON_SITE}"

# Install Linux-compatible wheels (manylinux) so the layer works in Lambda
pip install \
  --requirement "${BACKEND_ROOT}/requirements.txt" \
  --target "${PYTHON_SITE}" \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --python-version 3.12 \
  --only-binary :all: \
  --upgrade \
  --quiet

echo "==> Creating lambda_layer.zip (using Python zipfile — no zip binary needed)"
mkdir -p "${BUILD_DIR}"
python3 -c "
import zipfile, os, sys
layer_dir, output_zip = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(output_zip, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(layer_dir):
        for file in files:
            fp = os.path.join(root, file)
            arcname = os.path.relpath(fp, layer_dir)
            zf.write(fp, arcname)
size_mb = os.path.getsize(output_zip) / (1024 * 1024)
print(f'Created: {output_zip} ({size_mb:.1f} MB)')
" "${LAYER_DIR}" "${BUILD_DIR}/lambda_layer.zip"

echo "==> Lambda layer built: ${BUILD_DIR}/lambda_layer.zip"
