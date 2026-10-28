import Foundation

/// Website rules support a hostname or a leading `*.` for its subdomains.
enum DomainPattern {
    static func normalize(_ input: String) throws -> String {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard raw.contains("*") else { return try WebURL.normalizeDomain(raw) }
        guard raw.hasPrefix("*."), !raw.dropFirst(2).contains("*"),
              let suffix = try? WebURL.normalizeDomain(String(raw.dropFirst(2))),
              !suffix.contains(":") else {
            throw PickerError.invalidRule("Use a leading wildcard followed by a hostname, such as *.github.io.")
        }
        return "*." + suffix
    }

    static func matches(_ host: String, pattern: String, includeSubdomains: Bool) -> Bool {
        if pattern.hasPrefix("*.") {
            // Keep the dot so lookalikes and the bare hostname cannot match.
            return host.hasSuffix(pattern.dropFirst())
        }
        return host == pattern || (includeSubdomains && host.hasSuffix("." + pattern))
    }
}
