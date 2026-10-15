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
- `appcast.xml`: signed update feed pointing to this exact release's signed ZIP.

The main download is `https://github.com/maxyurk/browser-picker/releases/latest/download/Browser-Picker.dmg`.

## Version source

`scripts/version.py` writes `CFBundleShortVersionString` from the tag and `CFBundleVersion` from the Git commit count. Both architectures must report identical version, source commit, and build number before they can be combined. Build metadata and the MIT license are included in the app bundle.

A local checkout uses its highest reachable SemVer tag. Before the first tag, or when building a source archive without Git metadata, the development version is `0.0.0`. Use `BROWSER_PICKER_RELEASE_TAG=v1.2.3 ./scripts/build.sh release` to stamp an explicit version for a development packaging check. Publishing is performed by GitHub Actions against a verified source commit.

## Signing and validation

Sparkle verifies the update feed and ZIP using Ed25519 signatures before extraction. An invalid feed never falls back to unsigned metadata. The feed is served from `releases/latest/download/appcast.xml`; archive URLs include their exact version tag. Checks use the static download endpoint, not GitHub's rate-limited API. Automatic checking is weekly; a downloaded update may be offered after two weeks if the app has not quit. Customers can disable checks or automatic downloads in Settings → Updates.

Before the first updater-enabled release, create a dedicated Sparkle signing key in the maintainer's macOS Keychain, put **only its public key** in `Resources/UpdatePublicKey.txt`, and store its private key in the repository's encrypted GitHub Actions secret named `SPARKLE_ED25519_PRIVATE_KEY`. Creating and storing this release-authorizing credential requires the maintainer's explicit approval. The setup has not been activated while the public-key file is empty. Never commit a private key or include one in release assets, logs, or command-line arguments. Keep a separate secure backup: ad-hoc signed releases cannot recover from a lost update-signing key by rotating a Developer ID identity.

Use the pinned framework's `generate_keys --account com.github.maxyurk.browser-picker` tool after that approval. The same tool's `-p` option prints only the public key. Its `-x` option can securely export the private key for passing to `gh secret set` via standard input; remove the protected temporary export immediately afterward. Do not print its contents.

Release preflight stops before building or tagging if signing is unconfigured. Packaging generates the appcast with Sparkle's official tools, verifies the archive against the app's public key with CryptoKit, verifies the signed feed, and includes the feed in `SHA256SUMS.txt`. Published releases are immutable on retries. Development builds without a public key still build and run, with automatic updates disabled and a manual download link.

Downloads are ad-hoc signed. Apple Developer ID signing and notarization are not configured, so users may need **System Settings → Privacy & Security → Open Anyway** for their first launch. No signing credentials or private keys are stored in the repository.

The release jobs run the 94 core tests on both architectures. Native UI checks and real browser handoffs are also tested locally, as recorded in [TESTING.md](TESTING.md). Test release tooling locally with:

```sh
python3 -m unittest discover -s Tests/ReleaseTests
python3 scripts/test-updater.py
BROWSER_PICKER_RELEASE_TAG=v1.0.1 ./scripts/build.sh release
BROWSER_PICKER_RELEASE_TAG=v1.0.1 ./scripts/package-release.sh
```

CI builds use Xcode 16.4 on the `macos-15` and `macos-15-intel` runners. Runner labels and the available toolchain are documented by [GitHub's runner images](https://github.com/actions/runner-images). The workflow uses pinned official GitHub actions and grants repository write permission only to the publishing job.

The updater integration test uses disposable app bundles, loopback HTTP, and a publicly documented RFC 8032 test key. It never reads a production signing key, changes the installed app, or changes file/URL associations. Test keys must never be put into the production public-key file.
