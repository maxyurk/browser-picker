import AppKit
import Combine
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var status = "Checks GitHub weekly. No telemetry."
    private(set) var engine: SPUUpdater?
    private var started = false
    private var observations: [NSKeyValueObservation] = []
    private var pendingInstallation: (() -> Void)?
    var onChange: (() -> Void)?
    var mayRestart: () -> Bool = { true }

    init(enabled: Bool, bundle: Bundle = .main, userDriver: (any SPUUserDriver)? = nil) {
        super.init()
        guard enabled, let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            status = "Automatic updates aren’t available in this build."
            return
        }
        let driver = userDriver ?? QuietUpdateDriver(bundle: bundle)
        (driver as? QuietUpdateDriver)?.onMessage = { [weak self] in self?.status = $0 }
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: self)
        engine = updater
        for keyPath in [\SPUUpdater.canCheckForUpdates, \SPUUpdater.automaticallyChecksForUpdates, \SPUUpdater.automaticallyDownloadsUpdates] {
            observations.append(updater.observe(keyPath, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.objectWillChange.send(); self?.onChange?() }
            })
        }
    }

    var available: Bool { engine != nil }
    var canCheck: Bool { engine.map { !started || $0.canCheckForUpdates } ?? false }
    var automaticallyChecks: Bool {
        get { engine?.automaticallyChecksForUpdates ?? false }
        set { engine?.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyDownloads: Bool {
        get { engine?.automaticallyDownloadsUpdates ?? false }
        set { engine?.automaticallyDownloadsUpdates = newValue }
    }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func start() {
        guard let engine, !started else { return }
        do {
            try engine.start()
            started = true; onChange?()
        } catch {
            status = "Couldn’t start updates. Please try again later."
        }
    }
    func checkForUpdates() {
        start()
        guard let engine, started, engine.canCheckForUpdates else { return }
        engine.checkForUpdates()
    }
    func postponeInstallationIfBusy(_ install: @escaping () -> Void) -> Bool {
        guard !mayRestart() else { return false }
        pendingInstallation = install
        return true
    }
    func resumeInstallationIfIdle() {
        guard pendingInstallation != nil, mayRestart() else { return }
        let install = pendingInstallation; pendingInstallation = nil
        install?()
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        postponeInstallationIfBusy(installHandler)
    }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        status = "An update is ready. It will install when you quit."
        onChange?()
        return false // Sparkle keeps ownership of the safe install-on-quit path.
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        pendingInstallation = nil
        if let error {
            let error = error as NSError
            if error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue) {
                status = QuietUpdateDriver.noUpdateMessage(error)
            } else {
                // No alert and no immediate retry: Sparkle persists its last-check
                // date and resumes the normal weekly schedule after failures.
                status = "Couldn’t update right now. Please try again later."
            }
        }
        objectWillChange.send(); onChange?()
    }
}
