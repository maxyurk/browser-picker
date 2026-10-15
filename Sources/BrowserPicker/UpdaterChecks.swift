import AppKit
import Sparkle

@MainActor
enum UpdaterChecks {
    // RFC 8032 public test vector. This is not a production signing key.
    private static let testPublicKey = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="

    static func run(_ app: AppDelegate, check: (Bool, String) -> Void) {
        let info = Bundle.main.infoDictionary ?? [:]
        check((info["SUScheduledCheckInterval"] as? NSNumber)?.intValue == 604800, "automatic update checks are weekly")
        check((info["SUScheduledImpatientCheckInterval"] as? NSNumber)?.intValue == 1209600, "downloaded update reminders are less frequent than checks")
        check(info["SUEnableSystemProfiling"] as? Bool == false, "updater system profiling is disabled")
        check(info["SURequireSignedFeed"] as? Bool == true && info["SUVerifyUpdateBeforeExtraction"] as? Bool == true, "feeds and archives require signing")
        check((info["SUSignedFeedFailureExpirationInterval"] as? NSNumber)?.intValue == 0, "feed signing failures never fall back to untrusted data")
        check(info["SUFeedURL"] as? String == "https://github.com/maxyurk/browser-picker/releases/latest/download/appcast.xml", "update checks use a static release asset instead of the GitHub API")
        check(!app.store.updater.available && !app.store.updater.canCheck, "isolated test runs never start the real updater")
        let item = app.statusItem?.menu?.items.first { $0.title == "Check for Updates…" }
        check(item != nil && item!.target === app && !app.validateMenuItem(item!), "menu exposes a validated manual update action")

        let windowsBefore = NSApp.windows.filter(\.isVisible).map(\.windowNumber)
        let driver = QuietUpdateDriver(bundle: .main)
        var messages: [String] = []
        var acknowledged = 0
        driver.onMessage = { messages.append($0) }
        driver.showUserInitiatedUpdateCheck(cancellation: {})
        check(messages.last == "Checking for updates…", "manual checks have quiet inline progress")
        let noUpdate = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue), userInfo: [SPUNoUpdateFoundReasonKey: NSNumber(value: SPUNoUpdateFoundReason.onLatestVersion.rawValue)])
        driver.showUpdateNotFoundWithError(noUpdate) { acknowledged += 1 }
        check(messages.last == "You’re up to date." && acknowledged == 1, "no-update checks finish without an alert")
        let unsupported = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue), userInfo: [SPUNoUpdateFoundReasonKey: NSNumber(value: SPUNoUpdateFoundReason.systemIsTooOld.rawValue)])
        check(QuietUpdateDriver.noUpdateMessage(unsupported) == "No compatible update is available for this Mac.", "unsupported macOS does not falsely report the app is current")
        for code in [URLError.notConnectedToInternet, .timedOut, .cannotConnectToHost] {
            driver.showUpdaterError(URLError(code)) { acknowledged += 1 }
        }
        check(acknowledged == 4 && messages.last == "Couldn’t update right now. Please try again later.", "offline, timeout, and connection errors finish quietly")
        check(NSApp.windows.filter(\.isVisible).map(\.windowNumber) == windowsBefore, "failed and no-update checks create no windows")
        check(app.store.errorMessage == nil, "update failures do not leak into routing settings errors")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("picker-updater-" + UUID().uuidString)
        var domains: [String] = []
        defer {
            for domain in domains { UserDefaults.standard.removePersistentDomain(forName: domain) }
            try? FileManager.default.removeItem(at: directory)
        }
        func fixture(key: String?, feed: String = "https://example.com/appcast.xml") throws -> Bundle {
            let id = "test.browser-picker." + UUID().uuidString
            domains.append(id)
            let contents = directory.appendingPathComponent(id + ".app/Contents")
            try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            var value = info
            value["CFBundleIdentifier"] = id; value["CFBundleVersion"] = "1"
            value["SUDefaultsDomain"] = id; value["SUFeedURL"] = feed
            value["SUPublicEDKey"] = key; value["SUEnableAutomaticChecks"] = false
            try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
            try Data().write(to: contents.appendingPathComponent("MacOS/BrowserPicker"))
            UserDefaults(suiteName: id)?.set(Date(), forKey: "SULastCheckTime")
            return Bundle(url: contents.deletingLastPathComponent())!
        }
        do {
            let bundle = try fixture(key: testPublicKey)
            let updater = AppUpdater(enabled: true, bundle: bundle)
            check(updater.available && updater.canCheck, "a configured app exposes its updater before deferred startup")
            check(updater.engine?.updateCheckInterval == 604800, "Sparkle receives the weekly check interval")
            check(updater.allowedSystemProfileKeys(for: updater.engine!) == [], "system profile data stays disabled even with overridden defaults")
            updater.start(); updater.start()
            check(updater.engine?.canCheckForUpdates == true, "updater startup succeeds and is idempotent")
            check(!updater.automaticallyChecks, "updater respects an explicit automatic-check preference")
            updater.automaticallyDownloads = false
            let reloaded = AppUpdater(enabled: true, bundle: bundle)
            check(!reloaded.automaticallyDownloads, "updater download preference persists across relaunches")
            updater.updater(updater.engine!, didFinishUpdateCycleFor: .updatesInBackground, error: URLError(.notConnectedToInternet))
            check(updater.status == "Couldn’t update right now. Please try again later.", "background failures use a quiet, recoverable status")

            var busy = true; var installs = 0
            updater.mayRestart = { !busy }
            check(updater.postponeInstallationIfBusy { installs += 1 }, "updates wait while link handling is busy")
            updater.resumeInstallationIfIdle()
            check(installs == 0, "pending links prevent an update restart")
            busy = false; updater.resumeInstallationIfIdle(); updater.resumeInstallationIfIdle()
            check(installs == 1, "an idle app resumes deferred installation exactly once")
            check(!updater.postponeInstallationIfBusy {}, "an idle app permits installation immediately")

            let missing = AppUpdater(enabled: true, bundle: try fixture(key: nil))
            missing.start(); missing.checkForUpdates()
            check(!missing.available && !missing.canCheck, "missing signing keys disable updates without affecting the app")
            let invalid = AppUpdater(enabled: true, bundle: try fixture(key: "invalid"))
            check(!invalid.available, "malformed signing keys cannot enable the updater")
        } catch {
            check(false, "updater fixtures succeed: \(error)")
        }
    }
}
