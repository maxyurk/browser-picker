import Foundation
import Darwin

public enum WebURL {
    public static func parse(_ input: String, allowBareHost: Bool = false) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 65_536,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }) else { throw PickerError.invalidURL }
        let candidate = allowBareHost && !text.contains("://") ? "https://" + text : text
        guard let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.port.map({ (1...65535).contains($0) }) ?? true else { throw PickerError.invalidURL }
        if let host = components.host, host.hasPrefix("[") {
            let literal = String(host.dropFirst().dropLast())
            let address = String(literal.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            guard host.hasSuffix("]"), address.contains(":"), (try? normalizeDomain(address)) != nil else { throw PickerError.invalidURL }
        }
        // URL(string:) repairs bad percent escapes; reject them rather than alter signed links.
        let bytes = Array(candidate.utf8)
        for i in bytes.indices where bytes[i] == 37 {
            guard i + 2 < bytes.count, isHex(bytes[i + 1]), isHex(bytes[i + 2]) else { throw PickerError.invalidURL }
        }
        return url
    }
    private static func isHex(_ byte: UInt8) -> Bool { (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) }
    public static func normalizeDomain(_ input: String) throws -> String {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.contains(":") {
            let literal = raw.hasPrefix("[") && raw.hasSuffix("]") ? String(raw.dropFirst().dropLast()) : raw
            guard literal.allSatisfy({ $0.isASCII && ("0123456789abcdef:.".contains($0)) }) else { throw PickerError.invalidDomain }
            var address = in6_addr()
            guard literal.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { throw PickerError.invalidDomain }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else { throw PickerError.invalidDomain }
            let canonical = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            return "[" + String(decoding: canonical, as: UTF8.self) + "]"
        }
        guard !raw.isEmpty, !raw.contains(where: { "/:@?#%* []".contains($0) }),
              let url = try? parse("https://" + raw), let host = url.host?.lowercased() else { throw PickerError.invalidDomain }
        let domain = host.hasSuffix(".") ? String(host.dropLast()) : host
        guard domain.utf8.count <= 253, !domain.hasPrefix("."), !domain.contains(".."),
              domain.split(separator: ".").allSatisfy({ !$0.hasPrefix("-") && !$0.hasSuffix("-") && $0.utf8.count <= 63 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }) else { throw PickerError.invalidDomain }
        return domain
    }
    public static func process(_ input: URL, unwrap: Bool, cleanTracking: Bool) throws -> URL {
        var result = try parse(input.absoluteString)
        if unwrap {
            var seen: Set<String> = [result.absoluteString]
            for _ in 0..<5 {
                guard let next = unwrapped(result), seen.insert(next.absoluteString).inserted else { break }
                result = next
            }
        }
        return cleanTracking ? cleaned(result) : result
    }
    private static func unwrapped(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let key: String
        if (host == "www.google.com" || host == "google.com") && url.path == "/url" {
            key = parts.queryItems?.contains(where: { $0.name == "url" }) == true ? "url" : "q"
        } else if host == "safelinks.protection.outlook.com" || host.hasSuffix(".safelinks.protection.outlook.com") {
            key = "url"
        } else if (host == "l.facebook.com" || host == "lm.facebook.com") && url.path == "/l.php" {
            key = "u"
        } else { return nil }
        guard let value = parts.queryItems?.first(where: { $0.name == key })?.value else { return nil }
        return try? parse(value)
    }
    private static func cleaned(_ url: URL) -> URL {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let query = parts.percentEncodedQuery else { return url }
        let pairs = query.split(separator: "&", omittingEmptySubsequences: false).map(String.init)
        func key(_ pair: String) -> String { String(pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0]).removingPercentEncoding?.lowercased() ?? "" }
        let signatureKeys: Set<String> = ["signature", "sig", "hmac", "x-amz-signature", "x-goog-signature", "oauth_signature", "policy", "token", "access_token"]
        if pairs.contains(where: { signatureKeys.contains(key($0)) }) { return url }
        let trackers: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "_hsenc", "_hsmi"]
        let kept = pairs.filter { !key($0).hasPrefix("utm_") && !trackers.contains(key($0)) }
        guard kept.count != pairs.count else { return url }
        // Work with the original string so encoding, +, ordering, and fragments survive unchanged.
        let original = url.absoluteString
        guard let start = original.firstIndex(of: "?") else { return url }
        let end = original[start...].firstIndex(of: "#") ?? original.endIndex
        let suffix = String(original[end...])
        let replacement = String(original[..<start]) + (kept.isEmpty ? "" : "?" + kept.joined(separator: "&")) + suffix
        return URL(string: replacement) ?? url
    }
}
