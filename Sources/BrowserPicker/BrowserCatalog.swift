import AppKit
import PickerCore

@MainActor
enum BrowserCatalog {
    static func application(at url: URL) -> Bundle? {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !id.isEmpty,
              id.caseInsensitiveCompare(Bundle.main.bundleIdentifier ?? "") != .orderedSame,
              bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String != "BrowserPicker",
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        return bundle
    }
    static func discover(customPaths: [String] = []) -> [Destination] {
        let workspace = NSWorkspace.shared
        let registered = ["http", "https"].flatMap { workspace.urlsForApplications(toOpen: URL(string: $0 + "://example.com")!) }
        var applications: [String: Bundle] = [:]
        for url in registered {
            guard let bundle = application(at: url), let id = bundle.bundleIdentifier,
                  BrowserSupport.isBrowser(info: bundle.infoDictionary ?? [:], registeredForWebURLs: true) else { continue }
            if applications[id] == nil { applications[id] = bundle }
            // Choose macOS's preferred copy consistently when multiple versions exist.
            if let preferred = workspace.urlForApplication(withBundleIdentifier: id), let primary = application(at: preferred),
               BrowserSupport.isBrowser(info: primary.infoDictionary ?? [:], registeredForWebURLs: true) { applications[id] = primary }
        }
        for path in customPaths where path.hasPrefix("/") {
            if let bundle = application(at: URL(fileURLWithPath: path)), let id = bundle.bundleIdentifier { applications[id] = bundle }
        }
        let sorted = applications.values.sorted {
            let left = BrowserSupport.displayName(info: $0.infoDictionary ?? [:], fallback: $0.bundleURL.deletingPathExtension().lastPathComponent)
            let right = BrowserSupport.displayName(info: $1.infoDictionary ?? [:], fallback: $1.bundleURL.deletingPathExtension().lastPathComponent)
            let order = left.localizedStandardCompare(right)
            return order == .orderedSame ? ($0.bundleIdentifier ?? "") < ($1.bundleIdentifier ?? "") : order == .orderedAscending
        }
        var destinations: [Destination] = []
        for bundle in sorted {
            let id = bundle.bundleIdentifier!
            let app = bundle.bundleURL
            let info = bundle.infoDictionary ?? [:]
            let name = BrowserSupport.displayName(info: info, fallback: app.deletingPathExtension().lastPathComponent)
            let dataSubdirectory = BrowserSupport.chromiumDataSubdirectory(info: info, bundleID: id)
            destinations.append(Destination(id: id, name: name, bundleID: id, appPath: app.path, supportsPrivate: dataSubdirectory != nil))
            if let dataSubdirectory {
                let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support").appendingPathComponent(dataSubdirectory)
                if let data = try? Data(contentsOf: root.appendingPathComponent("Local State")) {
                    for profile in ChromeProfiles.read(data) where directoryExists(root.appendingPathComponent(profile.directory)) {
                        destinations.append(Destination(id: id + ":" + profile.directory, name: name + " · " + profile.name, bundleID: id, appPath: app.path, profile: profile.directory, supportsPrivate: true))
                    }
                }
            }
        }
        return destinations
    }
    static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

@MainActor
final class BrowserLauncher {
    var simulated = false
    var onSimulatedOpen: ((URL, Destination, Bool, Bool) -> Void)?
    func open(_ url: URL, in destination: Destination, privateWindow: Bool, background: Bool, completion: @escaping @MainActor (Error?) -> Void) {
        if simulated { onSimulatedOpen?(url, destination, privateWindow, background); completion(nil); return }
        let appURL = URL(fileURLWithPath: destination.appPath)
        guard FileManager.default.fileExists(atPath: appURL.path), Bundle(url: appURL)?.bundleIdentifier == destination.bundleID else {
            completion(NSError(domain: "BrowserPicker", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(destination.name) is no longer installed. Choose another browser."]))
            return
        }
        if privateWindow && !destination.supportsPrivate { completion(PickerError.invalidRule("This browser does not support private-window routing.")); return }
        if destination.profile != nil || privateWindow {
            do {
                guard let subdirectory = BrowserSupport.chromiumDataSubdirectory(info: Bundle(url: appURL)?.infoDictionary ?? [:], bundleID: destination.bundleID) else {
                    throw PickerError.invalidRule("Profile and private-window routing are unavailable for this browser.")
                }
                if let profile = destination.profile {
                    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support").appendingPathComponent(subdirectory)
                    guard ChromeProfiles.validDirectory(profile), BrowserCatalog.directoryExists(root.appendingPathComponent(profile)) else { throw PickerError.invalidProfile }
                }
                let args = try ChromeProfiles.arguments(url: url, profile: destination.profile, privateWindow: privateWindow)
                // `open -n` delivers Chromium flags even to an already running browser.
                // The browser forwards them to its existing process; no shell involved.
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-n"] + (background ? ["-g"] : []) + ["-a", appURL.path, "--args"] + args
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                process.terminationHandler = { process in
                    let code = process.terminationStatus
                    Task { @MainActor in
                        completion(code == 0 ? nil : NSError(domain: "BrowserPicker", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "Could not launch \(destination.name). Choose another browser."]))
                    }
                }
                try process.run()
            } catch { completion(error) }
        } else {
            let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = !background
            configuration.allowsRunningApplicationSubstitution = false
            if url.isFileURL {
                // Opening a document makes Launch Services check that it exists.
                // Deliver its address as a URL event so the browser handles the file.
                let event = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                event.setParam(NSAppleEventDescriptor(string: url.absoluteString), forKeyword: AEKeyword(keyDirectObject))
                configuration.appleEvent = event
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                    Task { @MainActor in completion(error) }
                }
                return
            }
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
                Task { @MainActor in completion(error) }
            }
        }
    }
}
