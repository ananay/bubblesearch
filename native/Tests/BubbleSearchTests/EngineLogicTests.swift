import XCTest
@testable import bubblesearch

/// Binary-plist reader (used for rich-link previews) and contact-handle
/// normalization — both pure, both easy to break subtly.
final class EngineLogicTests: XCTestCase {

    // MARK: - BPlist

    func testBPlistParsesDictWithStringAndInt() throws {
        let source: [String: Any] = ["title": "Hello", "count": 42]
        let data = try PropertyListSerialization.data(fromPropertyList: source, format: .binary, options: 0)

        let parsed = try XCTUnwrap(BPlist.parse(data))
        let root = try XCTUnwrap(parsed.objects[parsed.top].dictionary)
        XCTAssertEqual(root["title"]?.string, "Hello")
        if case .int(let n) = root["count"] {
            XCTAssertEqual(n, 42)
        } else {
            XCTFail("count should decode as an int")
        }
    }

    func testBPlistParsesUnicodeStrings() throws {
        let source: [String: Any] = ["s": "déjà 👋"]
        let data = try PropertyListSerialization.data(fromPropertyList: source, format: .binary, options: 0)
        let parsed = try XCTUnwrap(BPlist.parse(data))
        let root = try XCTUnwrap(parsed.objects[parsed.top].dictionary)
        XCTAssertEqual(root["s"]?.string, "déjà 👋")
    }

    func testBPlistRejectsNonBplist() {
        XCTAssertNil(BPlist.parse(Data("not a plist".utf8)))
    }

    // MARK: - Contact handle normalization

    func testPhoneKeyNormalizesFormatting() {
        XCTAssertEqual(ContactsStore.phoneKey("+1 (925) 566-4252"), "9255664252")
        XCTAssertEqual(ContactsStore.phoneKey("925.566.4252"), "9255664252")
        XCTAssertEqual(ContactsStore.phoneKey("9255664252"), "9255664252")
    }

    func testPhoneKeyTakesLastTenDigitsForCountryCodes() {
        // +44 7911 123456 → 447911123456 → last 10
        XCTAssertEqual(ContactsStore.phoneKey("+44 7911 123456"), "7911123456")
    }

    func testPhoneKeyKeepsShortNumbersAsIs() {
        XCTAssertEqual(ContactsStore.phoneKey("5551234"), "5551234")
    }

    func testHandleKeyLowercasesEmailAndTrims() {
        XCTAssertEqual(ContactsStore.handleKey(" Foo@Example.COM "), "foo@example.com")
    }

    func testHandleKeyRoutesPhonesThroughPhoneKey() {
        XCTAssertEqual(ContactsStore.handleKey("+1 (925) 566-4252"), "9255664252")
    }
}
