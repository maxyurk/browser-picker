import Foundation

/// Files are passed through unchanged; only web links need URL cleanup.
public enum OpenTarget {
    public static func parse(_ input: String, allowBareHost: Bool = false) throws -> URL {
        // Do not trim paths, inspect their contents, or require them to exist.
        if input.hasPrefix("/") || input.hasPrefix("./") || input.hasPrefix("../") {
            return URL(fileURLWithPath: input)
        }
        if input.hasPrefix("~/") {
            return URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
        }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), url.isFileURL { return url }
        return try WebURL.parse(text, allowBareHost: allowBareHost)
    }

    public static func process(_ url: URL, unwrap: Bool, cleanTracking: Bool) throws -> URL {
        if url.isFileURL { return url }
        return try WebURL.process(url, unwrap: unwrap, cleanTracking: cleanTracking)
    }
}
