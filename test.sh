#!/bin/bash
# Runs the tests. With Xcode installed, `swift test` is enough; with only the
# Command Line Tools, the path to the Swift Testing framework has to be passed in.
set -euo pipefail
cd "$(dirname "$0")"

DEV=/Library/Developer/CommandLineTools/Library/Developer
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]]; then
    swift test \
        -Xswiftc -F -Xswiftc "$DEV/Frameworks" \
        -Xlinker -F -Xlinker "$DEV/Frameworks" \
        -Xlinker -rpath -Xlinker "$DEV/Frameworks" \
        -Xlinker -rpath -Xlinker "$DEV/usr/lib" \
        "$@"
else
    swift test "$@"
fi
