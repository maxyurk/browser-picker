#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
swiftc -O -swift-version 6 -parse-as-library -I .build/release/Modules \
    Sources/BrowserPicker/BrowserCatalog.swift scripts/BrowserLauncherChecks.swift \
    .build/release/PickerCore.build/*.o -o build/BrowserLauncherChecks
build/BrowserLauncherChecks
