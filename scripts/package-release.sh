#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
: "${BROWSER_PICKER_RELEASE_TAG:?Set the release tag before packaging}"
app="$PWD/build/Browser Picker.app"
python3 - "$app" <<'PY'
import json, os, plistlib, sys
from pathlib import Path
app=Path(sys.argv[1])
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
build=json.loads((app/'Contents/Resources/BuildInfo.json').read_text())
assert build['tag']==os.environ['BROWSER_PICKER_RELEASE_TAG']
assert info['CFBundleShortVersionString']==build['version']
assert info['CFBundleVersion']==build['build']
assert build['commit'], 'A release must record its source commit'
PY
codesign --verify --deep --strict "$app"
mkdir -p build/release
task_image_dir=$(mktemp -d /tmp/browser-picker-image.XXXXXX)
trap 'rm -rf "$task_image_dir"' EXIT
ditto "$app" "$task_image_dir/Browser Picker.app"
ln -s /Applications "$task_image_dir/Applications"
cp LICENSE "$task_image_dir/LICENSE.txt"
ditto -c -k --sequesterRsrc --keepParent "$app" build/release/Browser-Picker.zip
hdiutil create -ov -format UDZO -fs HFS+ -volname 'Browser Picker' -srcfolder "$task_image_dir" build/release/Browser-Picker.dmg
hdiutil verify build/release/Browser-Picker.dmg
cp "$app/Contents/Resources/BuildInfo.json" build/release/BuildInfo.json
python3 scripts/update_feed.py generate "$app" build/release
cd build/release
shasum -a 256 Browser-Picker.dmg Browser-Picker.zip BuildInfo.json appcast.xml > SHA256SUMS.txt
shasum -a 256 --check SHA256SUMS.txt
