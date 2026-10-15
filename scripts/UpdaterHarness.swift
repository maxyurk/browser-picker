// Disposable application used by test-updater.py, never included in a release.
import AppKit
import Sparkle

@MainActor
func record(_ outcome: String, error: Error? = nil) {
    let path = Bundle.main.object(forInfoDictionaryKey: "UpdateTestResult") as! String
    let result = ["outcome": outcome, "error": error?.localizedDescription ?? ""]
    try! JSONSerialization.data(withJSONObject: result).write(to: URL(fileURLWithPath: path), options: .atomic)
}

@MainActor
func finish(_ outcome: String, error: Error? = nil) {
    record(outcome, error: error)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
}

@MainActor
final class InstallTestDriver: NSObject, SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { fatalError("Tests configure update permission explicitly") }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement(); finish("no-update") }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement(); finish("error", error: error) }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}

@MainActor
final class HarnessDelegate: NSObject, NSApplicationDelegate {
    var updater: AppUpdater?
    var scheduledQuit = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" {
            finish("installed"); return
        }
        updater = AppUpdater(enabled: true, userDriver: InstallTestDriver())
        let mode = Bundle.main.object(forInfoDictionaryKey: "UpdateTestMode") as? String
        if mode == "auto-install" {
            updater!.onChange = { [weak self] in
                guard let self, !scheduledQuit, updater?.status == "An update is ready. It will install when you quit." else { return }
                scheduledQuit = true; record("ready-on-quit")
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            updater!.start()
        } else if mode == "background" {
            updater!.onChange = { [weak self] in
                if self?.updater?.status.hasPrefix("Couldn’t") == true { finish("error") }
            }
            updater!.start()
        } else if mode == "throttle" {
            updater!.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { finish("throttled") }
        } else {
            updater!.checkForUpdates()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) { finish("timeout") }
    }
}

@main
@MainActor
enum UpdaterHarness {
    static func main() {
        let app = NSApplication.shared
        let delegate = HarnessDelegate()
        app.delegate = delegate
        app.run()
    }
}
