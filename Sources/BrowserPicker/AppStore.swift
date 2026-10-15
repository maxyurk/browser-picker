import AppKit
import Combine
import PickerCore
import ServiceManagement

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var configuration: Configuration
    @Published private(set) var destinations: [Destination]
    @Published var settingsTab: SettingsTab = .general
    let updater: AppUpdater
    @Published var errorMessage: String?
    @Published var isDefault = false
    @Published var loginEnabled = false
    @Published var loginRequiresApproval = false
    @Published var makingDefault = false
    @Published var defaultBrowserSetupMessage: String?
    private let repository: SettingsRepository
    private let injectedDestinations: [Destination]?
    private var writable = true
    var onChange: (() -> Void)?
    var icons: [String: NSImage] = [:]
    var shownDestinations: [Destination] {
        let visible = destinations.filter { !configuration.hiddenDestinationIDs.contains($0.id) }
        return visible.isEmpty ? destinations : visible
    }
    init(settingsURL: URL? = nil, destinations: [Destination]? = nil) {
        let testFlags = ["--simulate", "--smoke-test", "--integration-test"]
        updater = AppUpdater(enabled: settingsURL == nil && !testFlags.contains(where: CommandLine.arguments.contains))
        injectedDestinations = destinations
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BrowserPicker")
        repository = SettingsRepository(url: settingsURL ?? root.appendingPathComponent("settings.json"))
        var loaded = Configuration()
        var errorText: String?
        do {
            let result = try repository.load(); loaded = result.configuration
            if result.recoveredFromBackup { errorText = "Settings were recovered from the last backup. The damaged file will be preserved when you save a change." }
        } catch {
            writable = false
            errorText = "Could not load settings: \(error.localizedDescription) Your original settings are preserved at \(repository.url.path). Changes cannot be saved until the file is repaired or moved."
        }
        configuration = loaded; self.destinations = destinations ?? BrowserCatalog.discover(customPaths: loaded.customBrowserPaths); errorMessage = errorText
        cacheIcons(); refreshStatus()
    }
    func cacheIcons() {
        for destination in destinations where icons[destination.appPath] == nil {
            icons[destination.appPath] = NSWorkspace.shared.icon(forFile: destination.appPath)
        }
    }
    @discardableResult
    func update(_ mutation: (inout Configuration) throws -> Void) -> Bool {
        guard writable else { errorMessage = "Settings are read-only because the original file could not be loaded. Repair or move \(repository.url.path), then restart the app."; return false }
        do {
            var copy = configuration; try mutation(&copy)
            try repository.save(copy)
            configuration = copy; onChange?(); return true
        } catch { errorMessage = "Could not save settings: " + error.localizedDescription; return false }
    }
    func refresh() { destinations = injectedDestinations ?? BrowserCatalog.discover(customPaths: configuration.customBrowserPaths); icons.removeAll(); cacheIcons(); refreshStatus(); onChange?() }
    func addBrowser(_ url: URL) {
        guard let bundle = BrowserCatalog.application(at: url), let id = bundle.bundleIdentifier else {
            errorMessage = "Choose a runnable browser .app. Browser Picker cannot route links to itself."; return
        }
        if update({ config in
            config.customBrowserPaths.removeAll { Bundle(path: $0)?.bundleIdentifier == id || $0 == url.path }
            config.customBrowserPaths.append(url.standardizedFileURL.path)
            config.hiddenDestinationIDs.remove(id)
        }) { refresh() }
    }
    func forgetBrowserLocation(_ path: String) {
        if update({ $0.customBrowserPaths.removeAll { $0 == path } }) { refresh() }
    }
    func refreshStatus() {
        let previouslyDefault = isDefault
        isDefault = DefaultBrowserSetup.isActive(bundleID: Bundle.main.bundleIdentifier ?? "", handler: defaultHandler)
        if isDefault { defaultBrowserSetupMessage = nil }
        let loginStatus = SMAppService.mainApp.status
        loginRequiresApproval = loginStatus == .requiresApproval
        loginEnabled = loginStatus == .enabled || loginRequiresApproval
        if previouslyDefault != isDefault { onChange?() }
    }
    func makeDefault() {
        guard !makingDefault else { return }
        refreshStatus()
        if isDefault { return }
        makingDefault = true
        Task {
            defer { makingDefault = false }
            defaultBrowserSetupMessage = nil
            let result = await DefaultBrowserSetup.activate(bundleID: Bundle.main.bundleIdentifier ?? "", handler: defaultHandler) { scheme in
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
            }
            if case .needsSystemSettings = result {
                defaultBrowserSetupMessage = "Choose Browser Picker in System Settings → Desktop & Dock → Default web browser."
            }
            refreshStatus()
        }
    }
    private func defaultHandler(_ scheme: String) -> String? {
        guard let url = URL(string: scheme + "://example.com"), let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return Bundle(url: app)?.bundleIdentifier
    }
    func openDefaultBrowserSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") else { return }
        if !NSWorkspace.shared.open(url) {
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { errorMessage = "Could not change launch at login: " + error.localizedDescription }
        refreshStatus()
    }
    func remember(_ host: String, destination: Destination, privateWindow: Bool) {
        update { try $0.remember(domain: host, destinationID: destination.id, privateWindow: privateWindow) }
    }
}
