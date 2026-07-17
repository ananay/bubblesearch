import Foundation

/// Contact name + photo resolution from the AddressBook databases, plus
/// Messages' NickNameCache ("Share Name and Photo"). Same source chain as
/// the proven web version:
///   1. AddressBook photo blobs (ZTHUMBNAILIMAGEDATA/ZIMAGEDATA, 0x01-prefixed)
///   2. legacy AddressBook Images/ files (UUID-named)
///   3. NickNameCache images (NSKeyedArchiver handle→hash map)
/// Handles are keyed by last-10-digit phone / lowercase email; names are
/// cross-linked so a photo keyed by phone resolves for an email conversation.
final class ContactsStore {
    private(set) var names: [String: String] = [:] // handle key → display name

    /// Zero names on a machine with a Contacts database almost always means
    /// the AddressBook SQLite files were locked/busy during load — retryable.
    var isEmpty: Bool { names.isEmpty }

    private enum AvatarRef {
        case blob(dbPath: String, pk: Int64)
        case file(path: String)
    }

    private var avatarRefs: [String: AvatarRef] = [:] // handle key → photo
    private var nameRefs: [String: AvatarRef] = [:] // normalized name → photo
    private var blobDBs: [String: SQLiteDB] = [:]

    static func phoneKey(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        return digits.count > 10 ? String(digits.suffix(10)) : digits
    }

    static func handleKey(_ handle: String) -> String {
        handle.contains("@")
            ? handle.lowercased().trimmingCharacters(in: .whitespaces)
            : phoneKey(handle)
    }

    private static func nameKey(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    func name(for handle: String) -> String? {
        names[Self.handleKey(handle)]
    }

    func hasAvatar(handle: String, name: String? = nil) -> Bool {
        if avatarRefs[Self.handleKey(handle)] != nil { return true }
        if let name { return nameRefs[Self.nameKey(name)] != nil }
        return false
    }

    func avatarData(handle: String, name: String? = nil) -> Data? {
        let ref = avatarRefs[Self.handleKey(handle)] ?? name.flatMap { nameRefs[Self.nameKey($0)] }
        guard let ref else { return nil }
        switch ref {
        case .file(let path):
            return FileManager.default.contents(atPath: path)
        case .blob(let dbPath, let pk):
            guard let db = blobDB(dbPath) else { return nil }
            guard let row = try? db.query(
                "SELECT ZTHUMBNAILIMAGEDATA, ZIMAGEDATA FROM ZABCDRECORD WHERE Z_PK = ?", [.int(pk)]
            ).first else { return nil }
            return row.blob(0).flatMap { Self.decodeImageColumn($0, dbPath: dbPath) }
                ?? row.blob(1).flatMap { Self.decodeImageColumn($0, dbPath: dbPath) }
        }
    }

    /// AddressBook image columns come in two formats, distinguished by the
    /// first byte: 0x01 = inline image data follows; 0x02 = a NUL-terminated
    /// UUID string naming a file in the source's Core Data external storage
    /// (.AddressBook-v22_SUPPORT/_EXTERNAL_DATA/).
    private static func decodeImageColumn(_ data: Data, dbPath: String) -> Data? {
        guard let first = data.first else { return nil }
        switch first {
        case 0x01:
            let payload = data.dropFirst()
            return payload.count > 100 ? payload : nil
        case 0x02:
            guard let uuid = String(data: data.dropFirst(), encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                .trimmingCharacters(in: .whitespaces),
                  !uuid.isEmpty else { return nil }
            let sourceDir = (dbPath as NSString).deletingLastPathComponent
            let path = "\(sourceDir)/.AddressBook-v22_SUPPORT/_EXTERNAL_DATA/\(uuid)"
            return FileManager.default.contents(atPath: path)
        default:
            return data.count > 100 ? data : nil
        }
    }

    /// Cross-link a contact name to a photo-bearing handle (AddressBook name
    /// entries keep priority — only fills gaps).
    func linkName(_ name: String, handle: String) {
        let nk = Self.nameKey(name)
        guard !nk.isEmpty, nameRefs[nk] == nil, let ref = avatarRefs[Self.handleKey(handle)] else { return }
        nameRefs[nk] = ref
    }

    private func blobDB(_ path: String) -> SQLiteDB? {
        if let db = blobDBs[path] { return db }
        guard let db = try? SQLiteDB(path: path, readonly: true) else { return nil }
        blobDBs[path] = db
        return db
    }

    // MARK: - Loading

    func load() {
        // Idempotent: safe to call again after a failed/partial load.
        names.removeAll()
        avatarRefs.removeAll()
        nameRefs.removeAll()
        for db in blobDBs.values { _ = db } // handles close on dealloc
        blobDBs.removeAll()

        let fm = FileManager.default
        var sourceDirs = [Paths.addressBookDir]
        let sourcesRoot = "\(Paths.addressBookDir)/Sources"
        if let sources = try? fm.contentsOfDirectory(atPath: sourcesRoot) {
            sourceDirs += sources.map { "\(sourcesRoot)/\($0)" }
        }

        var keyMtime: [String: Date] = [:]
        var nameMtime: [String: Date] = [:]

        for dir in sourceDirs {
            let dbPath = "\(dir)/AddressBook-v22.abcddb"
            guard fm.fileExists(atPath: dbPath),
                  let db = try? SQLiteDB(path: dbPath, readonly: true) else { continue }
            let mtime = (try? fm.attributesOfItem(atPath: dbPath)[.modificationDate] as? Date) ?? .distantPast

            guard let rows = try? db.query(
                """
                SELECT r.Z_PK, r.ZUNIQUEID,
                       TRIM(COALESCE(r.ZFIRSTNAME,'') || ' ' || COALESCE(r.ZLASTNAME,'')),
                       r.ZORGANIZATION,
                       (r.ZTHUMBNAILIMAGEDATA IS NOT NULL OR r.ZIMAGEDATA IS NOT NULL),
                       p.ZFULLNUMBER, NULL
                FROM ZABCDPHONENUMBER p JOIN ZABCDRECORD r ON p.ZOWNER = r.Z_PK
                WHERE p.ZFULLNUMBER IS NOT NULL
                UNION ALL
                SELECT r.Z_PK, r.ZUNIQUEID,
                       TRIM(COALESCE(r.ZFIRSTNAME,'') || ' ' || COALESCE(r.ZLASTNAME,'')),
                       r.ZORGANIZATION,
                       (r.ZTHUMBNAILIMAGEDATA IS NOT NULL OR r.ZIMAGEDATA IS NOT NULL),
                       NULL, e.ZADDRESS
                FROM ZABCDEMAILADDRESS e JOIN ZABCDRECORD r ON e.ZOWNER = r.Z_PK
                WHERE e.ZADDRESS IS NOT NULL
                """
            ) else { continue }

            let imagesDir = "\(dir)/Images"
            for row in rows {
                let phone = row.text(5)
                let email = row.text(6)
                guard let raw = phone ?? email else { continue }
                let key = phone != nil
                    ? Self.phoneKey(raw)
                    : raw.lowercased().trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { continue }

                var displayName = row.text(2) ?? ""
                if displayName.isEmpty { displayName = row.text(3) ?? "" }
                if !displayName.isEmpty, names[key] == nil { names[key] = displayName }

                if (keyMtime[key] ?? .distantPast) >= mtime { continue }
                var ref: AvatarRef?
                if row.int(4) == 1 {
                    ref = .blob(dbPath: dbPath, pk: row.int(0) ?? 0)
                } else if let uid = row.text(1) {
                    let uuid = String(uid.split(separator: ":").first ?? "")
                    for candidate in ["\(imagesDir)/\(uuid).jpeg", "\(imagesDir)/\(uuid)"] {
                        if let attrs = try? fm.attributesOfItem(atPath: candidate),
                           (attrs[.size] as? Int ?? 0) > 0 {
                            ref = .file(path: candidate)
                            break
                        }
                    }
                }
                if let ref {
                    avatarRefs[key] = ref
                    keyMtime[key] = mtime
                }
            }

            // Name-keyed fallback: photos reachable when a conversation's handle
            // lives on a different card than the photo.
            if let named = try? db.query(
                """
                SELECT r.Z_PK, TRIM(COALESCE(r.ZFIRSTNAME,'') || ' ' || COALESCE(r.ZLASTNAME,''))
                FROM ZABCDRECORD r
                WHERE (r.ZTHUMBNAILIMAGEDATA IS NOT NULL OR r.ZIMAGEDATA IS NOT NULL)
                """
            ) {
                for row in named {
                    let nk = Self.nameKey(row.text(1) ?? "")
                    guard !nk.isEmpty, (nameMtime[nk] ?? .distantPast) < mtime else { continue }
                    nameRefs[nk] = .blob(dbPath: dbPath, pk: row.int(0) ?? 0)
                    nameMtime[nk] = mtime
                }
            }
        }

        loadNicknames()
    }

    /// "Share Name and Photo" images cached by Messages. The handle→file-hash
    /// mapping is an NSKeyedArchiver plist of plain strings.
    private func loadNicknames() {
        let fm = FileManager.default
        let dbPath = "\(Paths.nickNameCacheDir)/nicknameRecordsStore.db"
        guard fm.fileExists(atPath: dbPath),
              let db = try? SQLiteDB(path: dbPath, readonly: true),
              let row = try? db.query("SELECT value FROM kvtable WHERE key = 'activeNicknameRecords'").first,
              let blob = row.blob(0) else { return }

        let mapping: [String: String]
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: blob)
            unarchiver.requiresSecureCoding = false
            guard let dict = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [String: String] else { return }
            mapping = dict
        } catch { return }

        for (handle, hash) in mapping {
            let key = Self.handleKey(handle)
            guard !key.isEmpty, avatarRefs[key] == nil else { continue }
            let base = hash.replacingOccurrences(of: "/", with: "_")
            for suffix in ["-ad", "-wd", "-lrwd"] {
                let path = "\(Paths.nickNameCacheDir)/\(base)\(suffix)"
                if let attrs = try? fm.attributesOfItem(atPath: path), (attrs[.size] as? Int ?? 0) > 0 {
                    avatarRefs[key] = .file(path: path)
                    break
                }
            }
        }
    }
}
