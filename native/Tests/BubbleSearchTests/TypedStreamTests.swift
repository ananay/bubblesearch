import XCTest
@testable import bubblesearch

/// The typedstream decoder is the load-bearing, silently-breakable core of the
/// whole app (message text lives in these blobs). Fixtures are SYNTHETIC —
/// constructed to the format the decoder expects, never real message data.
final class TypedStreamTests: XCTestCase {

    /// Build a minimal-but-realistic NSAttributedString typedstream blob whose
    /// underlying NSString payload is `text`.
    private func makeBlob(_ text: String) -> Data {
        var bytes: [UInt8] = [0x04, 0x0b]
        bytes += Array("streamtyped".utf8) // header (contains no "NSString")
        bytes += [0x81, 0xe8, 0x03, 0x84, 0x01, 0x40]
        bytes += Array("NSString".utf8)
        let utf8 = Array(text.utf8)
        bytes += [0x01, 0x94, 0x84, 0x01, 0x2b] // class marker + '+' inline-bytes tag
        if utf8.count <= 0x7f {
            bytes += [UInt8(utf8.count)]
        } else if utf8.count <= 0xffff {
            bytes += [0x81, UInt8(utf8.count & 0xff), UInt8(utf8.count >> 8)]
        } else {
            bytes += [0x82,
                      UInt8(utf8.count & 0xff),
                      UInt8((utf8.count >> 8) & 0xff),
                      UInt8((utf8.count >> 16) & 0xff),
                      UInt8((utf8.count >> 24) & 0xff)]
        }
        bytes += utf8
        return Data(bytes)
    }

    func testDecodesPlainASCII() {
        XCTAssertEqual(TypedStream.decodeText(makeBlob("Hello, world!")), "Hello, world!")
    }

    func testDecodesMultibyteAndEmoji() {
        let text = "Café ☕️ — déjà vu 👋🏽"
        XCTAssertEqual(TypedStream.decodeText(makeBlob(text)), text)
    }

    func testDecodesLongStringViaTwoByteLength() {
        // Forces the 0x81 (u16) length path (> 127 UTF-8 bytes).
        let text = String(repeating: "abcde ", count: 60) // 360 bytes
        XCTAssertEqual(TypedStream.decodeText(makeBlob(text)), text)
    }

    func testReturnsNilForTooShortBlob() {
        XCTAssertNil(TypedStream.decodeText(Data([0x01, 0x02, 0x03])))
    }

    func testReturnsNilWhenNoNSString() {
        // 16+ bytes but no "NSString" marker anywhere.
        XCTAssertNil(TypedStream.decodeText(Data(repeating: 0x41, count: 32)))
    }

    func testCleanTextStripsAttachmentPlaceholderAndCollapsesWhitespace() {
        XCTAssertEqual(TypedStream.cleanText("Hello\u{FFFC} world"), "Hello world")
        XCTAssertEqual(TypedStream.cleanText("  multiple   spaces \n here "), "multiple spaces here")
        XCTAssertEqual(TypedStream.cleanText("\u{FFFC}"), "")
    }
}
