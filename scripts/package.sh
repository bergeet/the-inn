#!/bin/sh
# Run the tests, then zip the addon into dist/TheInn-<version>.zip
set -eu
cd "$(dirname "$0")/.."
luajit tests/run.lua >/dev/null || { luajit tests/run.lua | grep -A3 FAIL; echo "tests failed, not packaging"; exit 1; }
version=$(sed -n 's/^## Version: *//p' TheInn/TheInn.toc | tr -d '\r')
mkdir -p dist
out="dist/TheInn-$version.zip"
rm -f "$out"
zip -qr "$out" TheInn -x '*.DS_Store'
echo "$out"
