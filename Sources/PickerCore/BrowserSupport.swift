import Foundation

/// Vendor-independent metadata checks shared by discovery and launch validation.
public enum BrowserSupport {
    public static func isBrowser(info: [String: Any], registeredForWebURLs: Bool) -> Bool {
        guard registeredForWebURLs, info["LSUIElement"] as? Bool != true else { return false }
        // Terminals can register HTTP/HTML to forward them to the default browser.
        if ["com.googlecode.iterm2", "com.apple.Terminal"].contains(info["CFBundleIdentifier"] as? String ?? "") { return false }
        return (info["CFBundleDocumentTypes"] as? [[String: Any]] ?? []).contains { document in
            let role = (document["CFBundleTypeRole"] as? String ?? "Viewer").lowercased()
            guard role == "viewer" || role == "editor" else { return false }
            let types = (document["LSItemContentTypes"] as? [String] ?? []).map { $0.lowercased() }
            let extensions = (document["CFBundleTypeExtensions"] as? [String] ?? []).map { $0.lowercased() }
            let mimeTypes = (document["CFBundleTypeMIMETypes"] as? [String] ?? []).map { $0.lowercased() }
            return types.contains("public.html") || types.contains("public.xhtml") ||
                extensions.contains(where: { ["html", "htm", "xhtml"].contains($0) }) ||
                mimeTypes.contains(where: { ["text/html", "application/xhtml+xml"].contains($0) })
        }
    }

    public static func chromiumDataSubdirectory(info: [String: Any], bundleID: String) -> String? {
        // Chromium documents this key as the platform's default profile root.
        let value = info["CrProductDirName"] as? String ?? (bundleID == "com.google.Chrome" ? "Google/Chrome" : nil)
        guard let value, !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return value
    }

    public static func displayName(info: [String: Any], fallback: String) -> String {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = info[key] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
        }
        return fallback
    }
}
