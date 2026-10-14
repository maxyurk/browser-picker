# Verification — 14 October 2026

Tested on an Apple Silicon Mac, macOS 26.6.2, Swift 6.3.2. All reported checks passed on the final implementation. Finite testing cannot establish that software is 100% bug free.

## Automated tests

- **84 core tests**, zero failures; the complete suite was verified in debug and release after generic browser support. Covers URL validation, IDN and trailing-dot domains, equivalent IPv6 addresses, domain boundaries, source-app and path conditions, rule ordering, forced prompts, missing targets, private-window capabilities, remembered choices, lossless query cleanup, verified default-browser setup outcomes, outside-click defaults for older files, and persisting the disabled setting.
- **2,000 generated query cases** check raw encoding, repeated query parameters, fragments, and conservative tracker removal.
- **6,000 queued requests** exercise FIFO order, duplicates, compaction, interleaved appends, and reuse after draining.
- **100 settings saves** verify every saved result decodes correctly. Tests also cover missing files, atomic persistence, damaged-file preservation, backup recovery, invalid rules, failed saves, duplicate rule IDs, and refusing future schemas.
- Chrome tests cover profile enumeration, natural ordering, malformed metadata, directory traversal rejection, profile switches, incognito arguments, and URLs passed as a single argument without a shell.

## Native and system checks

- **120 native smoke assertions**, zero failures in the latest run with the app already selected as default. Real AppKit windows and SwiftUI settings; injected browser launcher. Checks keyboard focus after macOS activation, number and arrow selection, Tab wrapping, Return, system-dispatched keyboard events, Escape, exact URL copying with clipboard restoration, private/background flags, remembered choices, failed launch recovery/retry, fallback when all browsers are hidden, a 25-link picker burst, and confirming that an already active default produces no system request or warning. Command regressions exercise modifier changes with the checkbox focused, restoring unchecked and manually checked states, resetting on new links, native Command-number key equivalents for all four destinations, persisted website rules, an invalid number, private/background combinations, reserved Copy/Settings shortcuts, and a Command-4 event dispatched through NSApplication. Outside-click regressions cover inside clicks, stale opening clicks, disabling the option, a posted mouse event through the real local monitor, forwarding the event to its original window, dismissing without opening/remembering, duplicate callbacks, right/middle clicks, paused queue work, retained FIFO order, a new link after dismissal, and selecting a browser with the option enabled.
- **50 actual macOS URL deliveries** through `open -a`, all received and opened by the simulated launcher in order. Sender identity was unavailable for these command-line requests, as expected.
- **Six real browser handoffs**, all successful: Orion, Chrome, an installed Chrome profile, Safari, Chrome for Testing, and Chrome incognito. The incognito test page was additionally confirmed in Chrome's native UI. The handoff API/command succeeding does not independently verify the loaded page or account in every browser.
- Direct native mouse tests checked the picker layout, keyboard selection, rule editor, rejecting an empty rule, enabling profile-specific private routing, and saving a valid rule.
- Release bundle passes `codesign --verify --deep --strict`; Info.plist passes `plutil -lint`.

## Measured performance

These are observations on this Mac, not latency guarantees. No network work occurs in routing.

| Measurement | Result |
| --- | --- |
| Routing with 50 rules, 10,000 release samples | Median 13 µs; p95 16 µs; p99 23 µs |
| Warm picker display, final native smoke run | Median 3.6 ms; p95 7.9 ms |
| First picker display | 53 ms in the final run |
| Native startup to ready | 96–116 ms in final runs |
| Complete app bundle | About 1.2 MB |
| Installed app with Settings open, resident memory | About 105 MB, including native framework allocations |

Picker measurements time native view/window setup; they do not measure display scanout or human input. Browser handoff acceptance ranged from 27 to 387 ms in the real integration run, including a cold Safari launch. Browser startup and page load time are outside the picker engine.

## Issues found and resolved

- Cold-launch keyboard activation is asynchronous: activate the app, order the panel, and reassert key-window state after AppKit processes activation.
- Rebuilding native rows for every URL slowed repeated prompts: cache the complete destination models and reuse native views.
- Remembered choices could be persisted before a failed handoff: persist only after success.
- Rule controls could retain stale list indices: find current rules by ID and guard reorder bounds.
- A renamed browser/profile could retain a cached row title: invalidate views using the entire destination model.
- Corrupt settings with no usable backup could silently discard attempted UI edits: keep the file intact, explain read-only state, and keep failed rule saves in the editor.
- Cancellation and background selection restore the previous application's focus.
- Repeated default-browser requests are suppressed while macOS handles the first request.
- IPv6 hosts now support remembered choices and match equivalent compressed/expanded addresses.
- Host and path normalization are computed once per request, avoiding repeated Foundation work for each rule.
- The default setup button could show a raw macOS error even though both handlers already pointed to Browser Picker. Each scheme is now checked before requesting a change; actual state is verified after errors and no-op returns. Successful status clears setup guidance. Genuine failures offer the standard System Settings selection flow, with guidance confined to General.
- Eight setup regressions cover an already active app, an HTTP request updating both schemes, an error after successful changes, unchanged and partially changed defaults, no-op setters, separate scheme updates, and identifier casing/missing identity.
- Command-number shortcuts were blocked by the picker keyboard handler. They now open and remember the numbered browser. Holding Command visibly checks the remember control, changes the heading, and reveals Command-number badges. Releasing it restores the manual checkbox choice; focus changes refresh modifier state so the visual indication cannot stick after leaving the picker.
- Outside clicks now close the picker by default, with a persisted General preference. Local/global mouse observers exist only while the option is enabled and the picker is visible. Opening-click timestamps are ignored, clicks are not consumed, and closing does not restore focus over the clicked app. Pending prompts pause until resumed so an old asynchronous pump cannot immediately reopen the panel; remaining links stay available from the menu.

## Boundaries and remaining platform verification

The actual default-browser consent and launch-at-login consent flows are implemented with Apple's NSWorkspace and ServiceManagement APIs. The original tests preserved system preferences. After Browser Picker was selected as default, read-only diagnostics confirmed both installed handler paths and the native suite verified that Make Default does not repeat a system request or show a warning. Failed automatic requests offer System Settings → Desktop & Dock → Default web browser; consent and managed-policy restrictions still belong to macOS. Source-app rules require macOS to expose an identifiable sender. Private/profile routing for browsers without compatible Chromium metadata, browser extensions, universal-link interception, and online short-link expansion are outside the current implementation. Regular link routing now supports generic macOS browser apps.

The app is ad-hoc signed for local use. Notarization, distribution, updates, other machines, older macOS releases, long-running soak tests, and every browser version are not verified. No unresolved failures were found in the tested scope.

## Documentation and website verification

The public documentation update was checked with another passing run of all **74 core tests** and **99 native smoke assertions**. The screenshot helper compiles separately from the shipped app and renders production AppKit/SwiftUI views with neutral example profiles and rules. Five screenshots were exported and visually inspected; user settings and Chrome profile metadata are not loaded by the helper.

The static project website was checked in the browser at **320, 390, 768, and 1280 pixel** viewport widths. No horizontal overflow or broken images were found. Screenshot mode switching, its pressed state and caption, install-command copy feedback, anchor navigation, FAQ disclosure, and keyboard focus were checked. No browser console errors were reported.

All local website assets, fragment targets, README/contributor links, and the synchronized MIT license copies passed validation. Eight repository URL cases covered standard project Pages paths, account-root Pages, custom-domain metadata, local previews, and invalid configuration. JavaScript syntax passed Node's parser. These checks were performed locally; publication details are in [docs/README.md](docs/README.md).

## Generic browser support

Discovery now uses registered HTTP/HTTPS handlers and HTML-viewing bundle metadata. Manually selected browser apps bypass the discovery heuristic. Bundle identities deduplicate installed copies, explicitly added locations take precedence, and existing browser/profile destination IDs are preserved. Known terminal forwarding handlers and Browser Picker copies are excluded.

The core suite now has **84 tests**, including unknown browser metadata, legacy HTML declarations, non-browser handlers, malformed metadata, Chromium profile-root validation, backwards-compatible manual-location persistence, and routing to an arbitrary browser. Native catalog checks cover unregistered app fixtures, duplicate copies, self-routing prevention, removal, persistence/reload, and actual Launch Services results. The picker also checks a 40-destination list, keyboard scrolling, screen bounds, and refreshing a visible picker when browser visibility changes. Native keyboard tests use deterministic destinations so they work independently of the machine's browser inventory.

Profile and private-window support use Chromium's documented `CrProductDirName` metadata and standard flags. These capabilities are available only when compatible metadata is present (with a fallback for older Chrome bundles). Regular routing uses NSWorkspace for every browser. Tests do not establish compatibility with every browser version or vendor's private-window implementation.

Final generic-support verification: **84 core tests passed in debug and release**, **120 native smoke assertions passed on the installed build**, and **six real browser handoffs succeeded** (the detected browser destinations plus Chrome incognito). The public-identifier build passed 116 native assertions; it skips the four already-default checks because the existing Mac's registration retains its installation identity. The installed app retained both HTTP and HTTPS defaults. Code signing passed after installation.

A scroll-layout regression initially clipped shortcut badges. The document view now constrains its width to the clip viewport; native checks assert row widths, keyboard visibility, selection preservation, and screen bounds. Updated screenshots show the complete badges. Browser visibility changes preserve the selected browser identity while refreshing an open picker.

The native harness injects initial/focus modifier snapshots, while modifier-change and key events are exercised through AppKit. This keeps synthetic keyboard expectations independent of ambient desktop event state. Browser launches disable running-app substitution so a manually selected app location is respected.

The final explicit-location launcher build repeated all **six real browser handoffs with zero failures** and passed **120 native smoke assertions with zero failures**.
