import AppKit
import PickerCore

/// Opt-in real handoff tests. Opens example.com in the installed browsers; no settings changes.
@MainActor
enum BrowserIntegrationTests {
    static func run(_ app: AppDelegate) {
        var tests = app.store.destinations.map { ($0, false) }
        if let chrome = app.store.destinations.first(where: { $0.bundleID == "com.google.Chrome" && $0.profile == nil }) { tests.append((chrome, true)) }
        var failures: [String] = []
        let stamp = UUID().uuidString
        func next(_ index: Int) {
            guard index < tests.count else {
                app.journal(["event": "integration-result", "checks": tests.count, "failures": failures])
                print("Real browser handoffs: \(tests.count) checks, \(failures.count) failures \(failures)"); fflush(stdout)
                exit(failures.isEmpty ? 0 : 1)
            }
            let (destination, privateMode) = tests[index]
            let url = URL(string: "https://example.com/?picker-test=\(stamp)&case=\(index)")!
            let started = CFAbsoluteTimeGetCurrent()
            app.launcher.open(url, in: destination, privateWindow: privateMode, background: false) { error in
                let success = error == nil
                if !success { failures.append(destination.name + ": " + (error?.localizedDescription ?? "unknown error")) }
                app.journal(["event": "handoff", "destination": destination.id, "private": privateMode, "success": success, "url": url.absoluteString, "handoff_ms": (CFAbsoluteTimeGetCurrent() - started) * 1000])
                // Give the browser time to create the test window before the next handoff.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { next(index + 1) }
            }
        }
        next(0)
    }
}
