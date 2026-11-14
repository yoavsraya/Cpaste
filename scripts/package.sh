#!/bin/bash
# Builds the release app and zips it for sharing as dist/Cpaste.zip.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh release
mkdir -p dist
rm -f dist/Cpaste.zip
ditto -c -k --sequesterRsrc --keepParent build/Cpaste.app dist/Cpaste.zip
echo "packaged dist/Cpaste.zip ($(du -h dist/Cpaste.zip | cut -f1))"
