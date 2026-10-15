#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
output="${1:-$PWD/docs/assets}"
if [[ "$output" != /* ]]; then output="$PWD/$output"; fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
mkdir -p build
framework_dir="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
swiftc -O -swift-version 6 -parse-as-library -I .build/release/Modules \
    -F "$framework_dir" -framework Sparkle -Xlinker -rpath -Xlinker "$framework_dir" \
    Sources/BrowserPicker/AppUpdater.swift Sources/BrowserPicker/QuietUpdateDriver.swift \
    Sources/BrowserPicker/AppStore.swift Sources/BrowserPicker/BrowserCatalog.swift \
    Sources/BrowserPicker/PickerWindow.swift Sources/BrowserPicker/SettingsWindow.swift \
    scripts/ScreenshotExporter.swift .build/release/PickerCore.build/*.o \
    -o build/ScreenshotExporter
build/ScreenshotExporter "$output"
