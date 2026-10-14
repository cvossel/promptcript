#!/bin/bash
# Baut Promptcript.app in ./build. Mit --open wird die App danach gestartet.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Promptcript.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Promptcript "$APP/Contents/MacOS/Promptcript"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Fertig: $APP"

if [[ "${1:-}" == "--open" ]]; then
    open "$APP"
fi
