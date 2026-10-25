#!/bin/sh
# Compiles the Core logic with the Mac's Swift compiler and runs the checks. No Xcode needed.
set -e
cd "$(dirname "$0")"
work="$(mktemp -d)"
flags=""

# Command Line Tools 16 can ship two copies of the SwiftBridging module map, which breaks
# `import Foundation`. Hide the duplicate with a file overlay instead of touching system files.
dup=/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap
if [ -f "$dup" ] && [ -f "$(dirname "$dup")/module.modulemap" ]; then
    : > "$work/empty.modulemap"
    printf '{ "version": 0, "roots": [ { "type": "file", "name": "%s", "external-contents": "%s" } ] }\n' \
        "$dup" "$work/empty.modulemap" > "$work/overlay.yaml"
    flags="-vfsoverlay $work/overlay.yaml -module-cache-path $work/module-cache"
fi

swiftc -O $flags CaneGuide/Core/*.swift Checks/main.swift -o "$work/checks"
"$work/checks"
