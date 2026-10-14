#!/bin/bash
# Führt die Tests aus. Mit installiertem Xcode reicht `swift test`; mit den
# Command Line Tools allein muss der Pfad zum Swift-Testing-Framework mitgegeben werden.
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
