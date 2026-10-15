#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-release}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c "$configuration" --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
app="$PWD/build/Browser Picker.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
framework_dir="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
mkdir -p "$app/Contents/Frameworks"
ditto "$framework_dir/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE.txt"
if [[ ! -f build/AppIcon.icns || scripts/make-icon.swift -nt build/AppIcon.icns ]]; then
    swift scripts/make-icon.swift "$PWD/build/AppIcon.iconset"
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp ".build/$configuration/BrowserPicker" "$app/Contents/MacOS/BrowserPicker"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
python3 scripts/version.py --write-plist "$app/Contents/Info.plist" --metadata "$app/Contents/Resources/BuildInfo.json"
python3 scripts/update_feed.py configure "$app"
if [[ -f build/AppIcon.icns ]]; then cp build/AppIcon.icns "$app/Contents/Resources/"; fi
codesign --force --sign - "$app"
printf '%s\n' "$app"
