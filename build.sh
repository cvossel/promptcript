#!/bin/bash
# Builds Promptcript.app in ./build. With --open, the app is launched afterwards.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Promptcript.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Promptcript "$APP/Contents/MacOS/Promptcript"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Done: $APP"

if [[ "${1:-}" == "--open" ]]; then
    open "$APP"
fi
