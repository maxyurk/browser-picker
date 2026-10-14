# Releases

Open **Actions → Release macOS app → Run workflow** on GitHub, choose `main`, and select **patch**, **minor**, or **major**. Leave the explicit version blank for an automatic bump from the highest stable SemVer tag. The optional version field allows a specific version, such as `1.0.1`, provided it does not move an existing tag or create a lower new version.

The workflow tests versioning, builds and tests the app on Apple Silicon and Intel macOS runners, combines both binaries into a universal app, verifies signing and packaging, then creates the annotated `vMAJOR.MINOR.PATCH` tag and publishes the GitHub release. A failed build does not create a new tag. Existing published release assets are preserved on retries.

Pushing a stable tag such as `v1.2.3` also triggers the workflow for that exact commit. Do not move a published tag. Only stable three-part versions are supported; prerelease and build-metadata suffixes are rejected.

## Downloads

Every release has the same asset names so the website can always link directly to the latest release:

- `Browser-Picker.dmg`: universal app and an Applications shortcut.
- `Browser-Picker.zip`: the same app as a ZIP archive.
- `SHA256SUMS.txt`: SHA-256 hashes of the downloads and build metadata.
- `BuildInfo.json`: version, tag, source commit, build number, and architectures.

The main download is `https://github.com/maxyurk/browser-picker/releases/latest/download/Browser-Picker.dmg`.

## Version source

`scripts/version.py` writes `CFBundleShortVersionString` from the tag and `CFBundleVersion` from the Git commit count. Both architectures must report identical version, source commit, and build number before they can be combined. Build metadata and the MIT license are included in the app bundle.

A local checkout uses its highest reachable SemVer tag. Before the first tag, or when building a source archive without Git metadata, the development version is `0.0.0`. Use `BROWSER_PICKER_RELEASE_TAG=v1.2.3 ./scripts/build.sh release` to stamp an explicit version for a development packaging check. Publishing is performed by GitHub Actions against a verified source commit.

## Signing and validation

Downloads are ad-hoc signed. Apple Developer ID signing and notarization are not configured, so users may need **System Settings → Privacy & Security → Open Anyway** for their first launch. No signing credentials or private keys are stored in the repository.

The release jobs run the 94 core tests on both architectures. Native UI checks and real browser handoffs are also tested locally, as recorded in [TESTING.md](TESTING.md). Test release tooling locally with:

```sh
python3 -m unittest discover -s Tests/ReleaseTests
BROWSER_PICKER_RELEASE_TAG=v1.0.1 ./scripts/build.sh release
BROWSER_PICKER_RELEASE_TAG=v1.0.1 ./scripts/package-release.sh
```

CI builds use Xcode 16.4 on the `macos-15` and `macos-15-intel` runners. Runner labels and the available toolchain are documented by [GitHub's runner images](https://github.com/actions/runner-images). The workflow uses pinned official GitHub actions and grants repository write permission only to the publishing job.
