# Contributing

Browser Picker aims to stay small, native, and quick. Focused fixes and compatibility improvements are welcome.

## Work locally

Use macOS 14+ and a Swift 6+ toolchain. No third-party packages are required.

```sh
./scripts/test.sh
./scripts/build.sh release
open "build/Browser Picker.app"
```

The build signs the app locally. You do not need to change your default browser for core tests or simulated UI checks.

## Source layout

| Directory | Purpose |
| --- | --- |
| `Sources/PickerCore` | URL processing, rule matching, request queue, settings storage, browser metadata, and default-browser verification |
| `Sources/BrowserPicker` | App lifecycle, browser launching, AppKit picker, SwiftUI settings, and native integration checks |
| `Tests/PickerCoreTests` | XCTest regressions and generated cases |
| `scripts` | Build, install, tests, icon generation, and neutral screenshot export |
| `docs` | Static project website and shared README images |

## Validate a change

Run the core tests for routing or persistence changes. Test browser launch changes against the affected browser, including an already running instance. For picker or settings changes, run the native checks on a logged-in macOS desktop:

```sh
./scripts/test.sh -c release
./scripts/build.sh release
test_directory=$(mktemp -d /tmp/browser-picker-check.XXXXXX)
"build/Browser Picker.app/Contents/MacOS/BrowserPicker" \
  --simulate --test-settings "$test_directory/settings.json" \
  --journal "$test_directory/events.jsonl" --smoke-test
```

Use temporary settings and illustrative links. The `--journal` flag explicitly logs URLs; normal use does not. `--integration-test` opens real test pages in the installed browsers, so run it only when real handoffs need checking. See [TESTING.md](TESTING.md) for the existing verification record and its limits.

For file-launch changes, run `./scripts/test-file-handoffs.sh`. It creates a temporary native receiver and checks the actual addresses delivered on cold and warm launches, including nonexistent files and unknown extensions. It leaves your Browser Picker settings and file associations unchanged. To test a fixture in the installed browsers, add `--integration-file /absolute/path/to/fixture` to an integration run.

For documentation images, `./scripts/screenshots.sh` renders the production views with neutral fixtures, without reading your Browser Picker settings or Chrome profile metadata. It briefly presents native windows. Safari, Chrome, and Orion must be installed for their icons to appear. The helper executable is separate from the distributed app.

For the website, follow [docs/README.md](docs/README.md). Keep images, fonts, and scripts local, and preserve relative URLs so project-path GitHub Pages hosting works.

Release tooling has its own regressions: `python3 -m unittest discover -s Tests/ReleaseTests`. App version fields are generated from Git tags at build time; do not add a manual version to `Resources/Info.plist`. [RELEASING.md](RELEASING.md) describes the workflow.

## Report a bug or submit a change

Include the macOS and browser versions, exact reproduction steps, expected behavior, and an anonymized example URL when relevant. Remove tokens, account names, personal profile names, and private domains from logs and images. State which checks passed and which you could not run.

Add a regression test when it meaningfully protects against the failure. Keep routing work off the network and avoid extra work on the link-opening path. Explain any behavior or compatibility change in the pull request.

Contributions are covered by the repository's [MIT license](LICENSE).
