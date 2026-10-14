import AppKit

if CommandLine.arguments.contains("--diagnose-registration") {
    let schemes = ["http", "https"]
    let result: [String: Any] = [
        "bundleURL": Bundle.main.bundleURL.path,
        "bundleIdentifier": Bundle.main.bundleIdentifier ?? "nil",
        "executableURL": Bundle.main.executableURL?.path ?? "nil",
        "currentApplicationBundleURL": NSRunningApplication.current.bundleURL?.path ?? "nil",
        "handlers": Dictionary(uniqueKeysWithValues: schemes.map { scheme in
            (scheme, NSWorkspace.shared.urlsForApplications(toOpen: URL(string: scheme + "://example.com")!).map(\.path))
        }),
        "defaults": Dictionary(uniqueKeysWithValues: schemes.map { scheme in
            (scheme, NSWorkspace.shared.urlForApplication(toOpen: URL(string: scheme + "://example.com")!)?.path ?? "nil")
        })
    ]
    print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    exit(0)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
