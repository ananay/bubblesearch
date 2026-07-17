import Foundation

/// Minimal binary plist (bplist00) reader — enough to walk NSKeyedArchiver
/// archives with their UID references, which PropertyListSerialization
/// cannot expose. Used for rich-link (URL preview) payloads.
enum BPlist {
    indirect enum Value {
        case null
        case bool(Bool)
        case int(Int)
        case real(Double)
        case str(String)
        case data(Data)
        case uid(Int)
        case array([Value])
        case dict([String: Value])

        var string: String? { if case .str(let s) = self { return s }; return nil }
        var dictionary: [String: Value]? { if case .dict(let d) = self { return d }; return nil }
    }

    static func parse(_ data: Data) -> (objects: [Value], top: Int)? {
        let bytes = [UInt8](data)
        guard bytes.count > 40, String(decoding: bytes[0..<8], as: UTF8.self).hasPrefix("bplist00") else { return nil }

        let t = bytes.count - 32
        let offsetIntSize = Int(bytes[t + 6])
        let objectRefSize = Int(bytes[t + 7])
        let numObjects = readBE(bytes, t + 8, 8)
        let top = readBE(bytes, t + 16, 8)
        let offsetTableStart = readBE(bytes, t + 24, 8)

        var offsets: [Int] = []
        offsets.reserveCapacity(numObjects)
        for i in 0..<numObjects {
            offsets.append(readBE(bytes, offsetTableStart + i * offsetIntSize, offsetIntSize))
        }

        func readLength(_ pos: Int, _ info: Int) -> (len: Int, dataPos: Int) {
            guard info == 0xF else { return (info, pos) }
            let marker = Int(bytes[pos])
            let size = 1 << (marker & 0xF)
            return (readBE(bytes, pos + 1, size), pos + 1 + size)
        }

        func parseObject(_ index: Int) -> Value {
            guard index < offsets.count else { return .null }
            var pos = offsets[index]
            guard pos < bytes.count else { return .null }
            let marker = Int(bytes[pos])
            let type = marker >> 4
            let info = marker & 0xF
            pos += 1

            switch type {
            case 0x0:
                return info == 8 ? .bool(false) : info == 9 ? .bool(true) : .null
            case 0x1:
                return .int(readBE(bytes, pos, 1 << info))
            case 0x2:
                var value: Double = 0
                if info == 2 {
                    let bits = UInt32(truncatingIfNeeded: readBE(bytes, pos, 4))
                    value = Double(Float(bitPattern: bits))
                } else {
                    let bits = UInt64(bitPattern: Int64(readBE(bytes, pos, 8)))
                    value = Double(bitPattern: bits)
                }
                return .real(value)
            case 0x4:
                let (len, p) = readLength(pos, info)
                guard p + len <= bytes.count else { return .null }
                return .data(Data(bytes[p..<(p + len)]))
            case 0x5:
                let (len, p) = readLength(pos, info)
                guard p + len <= bytes.count else { return .null }
                return .str(String(decoding: bytes[p..<(p + len)], as: UTF8.self))
            case 0x6:
                let (len, p) = readLength(pos, info)
                guard p + len * 2 <= bytes.count else { return .null }
                var chars: [UInt16] = []
                chars.reserveCapacity(len)
                for i in 0..<len {
                    chars.append(UInt16(readBE(bytes, p + i * 2, 2)))
                }
                return .str(String(decoding: chars, as: UTF16.self))
            case 0x8:
                return .uid(readBE(bytes, pos, info + 1))
            case 0xA:
                let (len, p) = readLength(pos, info)
                var items: [Value] = []
                items.reserveCapacity(len)
                for i in 0..<len {
                    items.append(parseObject(readBE(bytes, p + i * objectRefSize, objectRefSize)))
                }
                return .array(items)
            case 0xD:
                let (len, p) = readLength(pos, info)
                var dict: [String: Value] = [:]
                for i in 0..<len {
                    let key = parseObject(readBE(bytes, p + i * objectRefSize, objectRefSize))
                    let value = parseObject(readBE(bytes, p + (len + i) * objectRefSize, objectRefSize))
                    if case .str(let k) = key { dict[k] = value }
                }
                return .dict(dict)
            default:
                return .null
            }
        }

        var objects: [Value] = []
        objects.reserveCapacity(numObjects)
        for i in 0..<numObjects {
            objects.append(parseObject(i))
        }
        return (objects, top)
    }

    private static func readBE(_ bytes: [UInt8], _ pos: Int, _ size: Int) -> Int {
        var value: UInt64 = 0
        for i in 0..<size where pos + i < bytes.count {
            value = value << 8 | UInt64(bytes[pos + i])
        }
        return Int(truncatingIfNeeded: value)
    }
}

/// Rich-link (URL preview) payload: an NSKeyedArchiver plist whose root holds
/// `richLinkMetadata` with title/siteName/URL. Verified against real payloads.
enum RichLink {
    static func parse(_ payload: Data) -> LinkPreview? {
        guard let (objects, _) = BPlist.parse(payload) else { return nil }

        func resolve(_ value: BPlist.Value?) -> BPlist.Value? {
            if case .uid(let n) = value, n < objects.count { return objects[n] }
            return value
        }
        func urlString(_ value: BPlist.Value?) -> String? {
            let resolved = resolve(value)
            if let s = resolved?.string { return s }
            if let d = resolved?.dictionary { return resolve(d["NS.relative"])?.string }
            return nil
        }

        // objects[1] is the archive root: { richLinkMetadata, richLinkIsPlaceholder }
        guard objects.count > 1,
              let root = objects[1].dictionary,
              let meta = resolve(root["richLinkMetadata"])?.dictionary
        else { return nil }

        let url = urlString(meta["URL"]) ?? urlString(meta["originalURL"])
        guard let url else { return nil }
        return LinkPreview(
            url: url,
            title: resolve(meta["title"])?.string,
            site: resolve(meta["siteName"])?.string
        )
    }
}
