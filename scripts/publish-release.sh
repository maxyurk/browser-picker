#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
: "${BROWSER_PICKER_RELEASE_TAG:?Missing release tag}"
: "${RELEASE_VERSION:?Missing release version}"
: "${RELEASE_COMMIT:?Missing release commit}"
: "${GITHUB_REPOSITORY:?Run this publisher from GitHub Actions}"
python3 scripts/version.py --tag "$BROWSER_PICKER_RELEASE_TAG" > /dev/null
test "$(git rev-parse HEAD)" = "$RELEASE_COMMIT"
python3 - <<'PY'
import json,os,sys
sys.path.insert(0,'scripts')
from version import parse_tag
info=json.load(open('build/release/BuildInfo.json'))
assert info['tag']==os.environ['BROWSER_PICKER_RELEASE_TAG']
assert info['version']==os.environ['RELEASE_VERSION']=='.'.join(map(str,parse_tag(info['tag'])))
assert info['commit']==os.environ['RELEASE_COMMIT']
assert info['architecture']=='universal' and info['architectures']==['arm64','x86_64']
PY
cd build/release
shasum -a 256 --check SHA256SUMS.txt
cd ../..
if git show-ref --verify --quiet "refs/tags/$BROWSER_PICKER_RELEASE_TAG"; then
    test "$(git rev-parse "refs/tags/$BROWSER_PICKER_RELEASE_TAG^{commit}")" = "$RELEASE_COMMIT"
else
    git config user.name 'github-actions[bot]'
    git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
    git tag -a "$BROWSER_PICKER_RELEASE_TAG" -m "Browser Picker $RELEASE_VERSION" "$RELEASE_COMMIT"
    git push origin "refs/tags/$BROWSER_PICKER_RELEASE_TAG"
fi
task_release_state="$PWD/build/release-state.json"
if gh release view "$BROWSER_PICKER_RELEASE_TAG" --json isDraft,targetCommitish,assets > "$task_release_state" 2>/dev/null; then
    if [[ $(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1]))["isDraft"]).lower())' "$task_release_state") == false ]]; then
        mkdir -p build/published
        gh release download "$BROWSER_PICKER_RELEASE_TAG" --pattern BuildInfo.json --dir build/published --clobber
        python3 - "$task_release_state" "$RELEASE_COMMIT" "$BROWSER_PICKER_RELEASE_TAG" <<'PY'
import json,sys
release=json.load(open(sys.argv[1]))
build=json.load(open('build/published/BuildInfo.json'))
assert build['commit']==sys.argv[2] and build['tag']==sys.argv[3], 'Published release was built from another commit or tag'
assets={asset['name'] for asset in release['assets'] if asset['size']>0}
assert {'Browser-Picker.dmg','Browser-Picker.zip','BuildInfo.json','SHA256SUMS.txt','appcast.xml'}<=assets, 'Published release is incomplete'
print('Release already published; keeping its original assets.')
PY
        exit 0
    fi
else
    cat > build/release-notes.md <<'NOTES'
A universal macOS app for Apple Silicon and Intel, requiring macOS 14 or later.

Download **Browser-Picker.dmg**, open it, and drag **Browser Picker.app** to **Applications**. Quit an existing copy before replacing it. Open the app and choose **Make default…** in General settings.

The app supports generic browsers, compatible Chromium profiles, website rules, Command-number shortcuts, and local files of any type. Routing stays on your Mac.

Automatic updates are now built in: verified updates are checked weekly from GitHub, downloaded in the background, and installed when you quit. Check manually or change update preferences in Settings → Updates. Failed checks stay quiet and retry on the normal schedule. No telemetry or link data is sent.

If you have version 1.0.1 or earlier, download this release once to enable future in-app updates.

This build is not Apple-notarized. After checking the source and release, try opening it from Applications and dismiss the first-launch warning. Choose **System Settings → Privacy & Security → Open Anyway** for Browser Picker, then confirm **Open**. No Terminal command, system-wide security change, or Xcode installation is required. Future in-app updates are verified with this project's separate update-signing key.

The ZIP is an alternative to the disk image. SHA256SUMS.txt verifies the downloads; BuildInfo.json records the tag, source commit, and architectures. Builds and core tests run on GitHub's Apple Silicon and Intel macOS runners.
NOTES
    gh release create "$BROWSER_PICKER_RELEASE_TAG" --verify-tag --target "$RELEASE_COMMIT" \
        --title "Browser Picker $RELEASE_VERSION" --draft --notes-file build/release-notes.md
fi
gh release upload "$BROWSER_PICKER_RELEASE_TAG" build/release/Browser-Picker.dmg build/release/Browser-Picker.zip build/release/BuildInfo.json build/release/SHA256SUMS.txt build/release/appcast.xml --clobber
task_latest_tag=$(gh api "repos/$GITHUB_REPOSITORY/releases/latest" --jq .tag_name 2>/dev/null || true)
task_is_latest=$(python3 - "$BROWSER_PICKER_RELEASE_TAG" "$task_latest_tag" <<'PY'
import sys
sys.path.insert(0,'scripts')
from version import parse_tag
try: latest=parse_tag(sys.argv[2])
except ValueError: latest=(0,0,0)
print(str(parse_tag(sys.argv[1])>=latest).lower())
PY
)
gh release edit "$BROWSER_PICKER_RELEASE_TAG" --draft=false --latest="$task_is_latest"
