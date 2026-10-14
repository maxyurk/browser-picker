import XCTest
@testable import PickerCore

final class WebURLTests: XCTestCase {
    func testValidURLs() throws {
        for input in ["https://example.com", "http://localhost:3000/a", "https://127.0.0.1:8443", "http://[::1]:8080/path", "https://example.com/a%20b?x=a+b&x=%2F#fragment", "HTTPS://EXAMPLE.COM", "https://例え.jp/路径", "https://user:password@example.com", "https://example.com./"] {
            XCTAssertNoThrow(try WebURL.parse(input), input)
        }
    }
    func testInvalidURLs() {
        for input in ["", "   ", "example.com", "javascript:alert(1)", "file:///tmp/a", "mailto:a@b.com", "https://", "https:///", "http://[invalid]/", "http://[127.0.0.1]/", "https://a.com:0", "https://a.com:65536", "https://a.com:-1", "https://a.com:x", "https://a.com/a b", "https://a.com/%", "https://a.com/%X1", "https://a.com/%0X", "https://a.com/\u{0}x", "https://a.com/\nx", String(repeating: "x", count: 65_537)] {
            XCTAssertThrowsError(try WebURL.parse(input), input)
        }
    }
    func testBareHostsAndWhitespace() throws {
        XCTAssertEqual(try WebURL.parse("  example.com/a?x=1  ", allowBareHost: true).absoluteString, "https://example.com/a?x=1")
        XCTAssertEqual(try WebURL.parse("localhost:3000/path", allowBareHost: true).host, "localhost")
        XCTAssertThrowsError(try WebURL.parse("hello world", allowBareHost: true))
    }
    func testDomainNormalization() throws {
        for (input, expected) in [(" EXAMPLE.com ", "example.com"), ("example.com.", "example.com"), ("localhost", "localhost"), ("127.0.0.1", "127.0.0.1"), ("bücher.de", "xn--bcher-kva.de")] {
            XCTAssertEqual(try WebURL.normalizeDomain(input), expected)
        }
    }
    func testIPv6DomainNormalization() throws {
        XCTAssertEqual(try WebURL.normalizeDomain("[0:0:0:0:0:0:0:1]"), "[::1]")
        XCTAssertEqual(try WebURL.normalizeDomain("[2001:DB8::1]"), "[2001:db8::1]")
        XCTAssertEqual(try WebURL.normalizeDomain("::1"), "[::1]")
        for input in ["[invalid]", "[:::1]", "[::1]:8080", "[::1/path]", "[::1%en0]"] {
            XCTAssertThrowsError(try WebURL.normalizeDomain(input), input)
        }
    }
    func testRejectInvalidDomains() {
        for domain in ["", "https://a.com", "a.com/path", "*.a.com", ".a.com", "a..com", "a.com:443", "user@a.com", "a.com?x=1", "a.com#fragment", "a_b.com", "-a.com", "a-.com", "a%2ecom", String(repeating: "a", count: 64) + ".com"] {
            XCTAssertThrowsError(try WebURL.normalizeDomain(domain), domain)
        }
    }
    func testTrackingPreservesEncodingOrderingAndFragment() throws {
        let url = URL(string: "https://example.com/a%2Fb?x=a+b&x=%2f&utm_source=x&keep=%26%3D&fbclid=123#hello%20world")!
        XCTAssertEqual(try WebURL.process(url, unwrap: false, cleanTracking: true).absoluteString, "https://example.com/a%2Fb?x=a+b&x=%2f&keep=%26%3D#hello%20world")
    }
    func testDisabledProcessingIsLossless() throws {
        let url = URL(string: "https://example.com/?utm_source=x&x=a+b#foo")!
        XCTAssertEqual(try WebURL.process(url, unwrap: false, cleanTracking: false), url)
    }
    func testRemoveOnlyTrackingQuery() throws {
        XCTAssertEqual(try WebURL.process(URL(string: "https://a.com/?utm_source=x&fbclid=1#foo")!, unwrap: false, cleanTracking: true).absoluteString, "https://a.com/#foo")
    }
    func testEmptyQueryDoesNotCrash() throws {
        for input in ["https://a.com/?", "https://a.com/?&", "https://a.com/?&utm_source=x&&", "https://a.com/?=x&utm_source=y"] {
            XCTAssertNoThrow(try WebURL.process(URL(string: input)!, unwrap: true, cleanTracking: true))
        }
    }
    func testSignedAndAuthenticationURLsAreUntouched() throws {
        for key in ["signature", "sig", "hmac", "X-Amz-Signature", "X-Goog-Signature", "oauth_signature", "policy", "token", "access_token"] {
            let url = URL(string: "https://a.com/?utm_source=x&\(key)=123&x=%2f")!
            XCTAssertEqual(try WebURL.process(url, unwrap: false, cleanTracking: true), url, key)
        }
    }
    func testEncodedTrackingNames() throws {
        XCTAssertEqual(try WebURL.process(URL(string: "https://a.com/?%75tm_source=x&%66bclid=x&q=x")!, unwrap: false, cleanTracking: true).absoluteString, "https://a.com/?q=x")
    }
    func testCaseInsensitiveTrackingNames() throws {
        XCTAssertEqual(try WebURL.process(URL(string: "https://a.com/?UTM_SOURCE=x&FBCLID=x&q=x")!, unwrap: false, cleanTracking: true).absoluteString, "https://a.com/?q=x")
    }
    func testGoogleRedirect() throws {
        let wrapper = URL(string: "https://www.google.com/url?q=https%3A%2F%2Fexample.com%2Fa%3Fx%3Da%2520b%26utm_source%3Dx&sa=x")!
        XCTAssertEqual(try WebURL.process(wrapper, unwrap: true, cleanTracking: true).absoluteString, "https://example.com/a?x=a%20b")
    }
    func testGoogleUrlParameter() throws {
        let wrapper = URL(string: "https://google.com/url?url=https%3A%2F%2Fa.com%2F")!
        XCTAssertEqual(try WebURL.process(wrapper, unwrap: true, cleanTracking: false).absoluteString, "https://a.com/")
    }
    func testOutlookSafelink() throws {
        let wrapper = URL(string: "https://nam01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com%2F%3Fq%3Dhello%252Bworld&data=123")!
        XCTAssertEqual(try WebURL.process(wrapper, unwrap: true, cleanTracking: false).absoluteString, "https://example.com/?q=hello%2Bworld")
    }
    func testFacebookRedirect() throws {
        let wrapper = URL(string: "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2F")!
        XCTAssertEqual(try WebURL.process(wrapper, unwrap: true, cleanTracking: false).absoluteString, "https://example.com/")
    }
    func testWrapperLookalikesAndUnsafeDestinationsAreNotUnwrapped() throws {
        for input in ["https://evilgoogle.com/url?q=https%3A%2F%2Fa.com", "https://google.com.evil.com/url?q=https%3A%2F%2Fa.com", "https://google.com/search?q=https%3A%2F%2Fa.com", "https://evil-safelinks.protection.outlook.com/?url=https%3A%2F%2Fa.com", "https://www.google.com/url?q=javascript%3Aalert(1)", "https://www.google.com/url?q=file%3A%2F%2F%2Ftmp%2Fa", "https://www.google.com/url?q=%", "https://example.com/?url=https%3A%2F%2Fa.com"] {
            let url = URL(string: input)!
            // Foundation percent-escapes a literal invalid % in this constructed test URL.
            XCTAssertEqual(try WebURL.process(url, unwrap: true, cleanTracking: false), url, input)
        }
    }
    func testNestedRedirects() throws {
        var url = URL(string: "https://example.com/?utm_source=x")!
        for _ in 0..<3 {
            var parts = URLComponents(string: "https://www.google.com/url")!
            parts.queryItems = [URLQueryItem(name: "q", value: url.absoluteString)]; url = parts.url!
        }
        XCTAssertEqual(try WebURL.process(url, unwrap: true, cleanTracking: true).absoluteString, "https://example.com/")
    }
    func testUnwrapHasBoundedDepth() throws {
        var url = URL(string: "https://example.com")!
        for _ in 0..<8 {
            var parts = URLComponents(string: "https://www.google.com/url")!
            parts.queryItems = [URLQueryItem(name: "q", value: url.absoluteString)]; url = parts.url!
        }
        XCTAssertEqual(try WebURL.process(url, unwrap: true, cleanTracking: false).host, "www.google.com")
    }
    func testFuzzQueriesPreserveNonTrackers() throws {
        var seed: UInt64 = 0x12345678
        for _ in 0..<2_000 {
            seed = seed &* 6364136223846793005 &+ 1
            let value = String(seed, radix: 16)
            let url = URL(string: "https://example.com/a?value=\(value)%2F+x&same=1&same=2&utm_source=\(value)#\(value)")!
            let output = try WebURL.process(url, unwrap: true, cleanTracking: true)
            XCTAssertEqual(output.absoluteString, "https://example.com/a?value=\(value)%2F+x&same=1&same=2#\(value)")
        }
    }
}
