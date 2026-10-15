import AppKit
import Sparkle

/// Keep failures and "up to date" results in Settings; use Sparkle's UI only
/// when there is an update to install or an installation in progress.
@MainActor
final class QuietUpdateDriver: NSObject, SPUUserDriver {
    private let standard: SPUStandardUserDriver
    var onMessage: ((String) -> Void)?

    init(bundle: Bundle) { standard = SPUStandardUserDriver(hostBundle: bundle, delegate: nil) }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standard.show(request, reply: reply)
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { onMessage?("Checking for updates…") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        onMessage?("An update is available.")
        standard.showUpdateFound(with: appcastItem, state: state, reply: reply)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) { standard.showUpdateReleaseNotes(with: downloadData) }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { standard.showUpdateReleaseNotesFailedToDownloadWithError(error) }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        onMessage?(Self.noUpdateMessage(error)); acknowledgement()
    }
    static func noUpdateMessage(_ error: Error) -> String {
        let reason = ((error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value
        if reason == SPUNoUpdateFoundReason.onLatestVersion.rawValue || reason == SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue {
            return "You’re up to date."
        }
        return "No compatible update is available for this Mac."
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        standard.dismissUpdateInstallation()
        onMessage?("Couldn’t update right now. Please try again later."); acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { standard.showDownloadInitiated(cancellation: cancellation) }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength) }
    func showDownloadDidReceiveData(ofLength length: UInt64) { standard.showDownloadDidReceiveData(ofLength: length) }
    func showDownloadDidStartExtractingUpdate() { standard.showDownloadDidStartExtractingUpdate() }
    func showExtractionReceivedProgress(_ progress: Double) { standard.showExtractionReceivedProgress(progress) }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { standard.showReady(toInstallAndRelaunch: reply) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        standard.showInstallingUpdate(withApplicationTerminated: applicationTerminated, retryTerminatingApplication: retryTerminatingApplication)
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }
    func dismissUpdateInstallation() { standard.dismissUpdateInstallation() }
    func showUpdateInFocus() { standard.showUpdateInFocus() }
}
