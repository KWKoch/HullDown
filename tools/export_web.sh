#!/bin/sh
# Web export + test-channel post-processing: network-first service worker and a build id the
# page checks whenever the app is opened or brought back, reloading if a newer build is live.
set -e
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/home/claude/godot_bin/Godot_v4.7.2-stable_linux.x86_64}
"$GODOT" --headless --path . --export-release "Web" docs/index.html
BUILD=$(date -u +%Y%m%d%H%M%S)
cp tools/web_sw.js docs/index.service.worker.js
sed -i "s/__BUILD_ID__/$BUILD/g" docs/index.html
printf '%s' "$BUILD" > docs/version.txt
echo "web build $BUILD"
