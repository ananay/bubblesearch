import Foundation

/// The search engine: owns the index database (same file + schema as the
/// TypeScript prototype, so an existing index is reused as-is) and the
/// contact/avatar store. Actor-isolated — SQLite connections stay confined.
actor Engine {
    private let index: SQLiteDB
    private let contacts = ContactsStore()

    private static let appleEpoch: TimeInterval = 978_307_200 // 2001-01-01 UTC

    init() throws {
        index = try SQLiteDB(path: Paths.indexDB)
        try index.exec(
            """
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
            CREATE TABLE IF NOT EXISTS messages (
              rowid INTEGER PRIMARY KEY,
              guid TEXT NOT NULL,
              chat_id INTEGER,
              sender TEXT,
              sender_name TEXT,
              is_from_me INTEGER NOT NULL,
              date_utc INTEGER NOT NULL,
              service TEXT,
              has_attachment INTEGER NOT NULL DEFAULT 0,
              text TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_messages_chat_date ON messages(chat_id, date_utc);
            CREATE INDEX IF NOT EXISTS idx_messages_date ON messages(date_utc);
            CREATE TABLE IF NOT EXISTS chats (
              chat_id INTEGER PRIMARY KEY,
              identifier TEXT,
              display_name TEXT,
              is_group INTEGER NOT NULL DEFAULT 0
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
              text,
              content='messages',
              content_rowid='rowid',
              tokenize="unicode61 remove_diacritics 2"
            );
            """
        )
        // Schema migrations for indexes built by older versions.
        try? index.exec("ALTER TABLE chats ADD COLUMN photo_path TEXT")
        try? index.exec("ALTER TABLE chats ADD COLUMN participants TEXT")
        try? index.exec("CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender)")
        contacts.load()
        Self.linkKnownSenders(index: index, contacts: contacts)
    }

    /// Cross-link names to photo-bearing handles using already-indexed senders.
    private static func linkKnownSenders(index: SQLiteDB, contacts: ContactsStore) {
        guard let rows = try? index.query(
            "SELECT DISTINCT sender, sender_name FROM messages WHERE sender IS NOT NULL AND is_from_me = 0"
        ) else { return }
        for row in rows {
            if let sender = row.text(0), let name = row.text(1) {
                contacts.linkName(name, handle: sender)
            }
        }
    }

    // MARK: - Contact reload / self-heal

    var contactsAvailable: Bool { !contacts.isEmpty }

    /// Retry loading contacts (AddressBook DBs can be transiently locked).
    /// On success, heals everything the failed load poisoned: chat display
    /// names and indexed sender names that fell back to raw handles.
    func reloadContacts() throws -> Bool {
        contacts.load()
        guard !contacts.isEmpty else { return false }
        Self.linkKnownSenders(index: index, contacts: contacts)
        try syncChats(liveDb()) // re-resolve chat display names
        try healSenderNames()
        return true
    }

    /// Fix indexed messages whose sender_name is still the raw handle.
    private func healSenderNames() throws {
        let unresolved = try index.query(
            "SELECT DISTINCT sender FROM messages WHERE sender IS NOT NULL AND is_from_me = 0 AND sender_name = sender"
        )
        try index.exec("BEGIN")
        defer { try? index.exec("COMMIT") }
        for row in unresolved {
            guard let sender = row.text(0),
                  let name = contacts.name(for: sender), name != sender else { continue }
            try index.run(
                "UPDATE messages SET sender_name = ? WHERE sender = ? AND is_from_me = 0",
                [.text(name), .text(sender)]
            )
        }
    }

    // MARK: - Indexing

    private static func toUnixSeconds(_ appleDate: Int64) -> Int64 {
        let secs = appleDate > 1_000_000_000_000 ? Double(appleDate) / 1e9 : Double(appleDate)
        return Int64(secs + appleEpoch)
    }

    func syncIndex(full: Bool = false) throws -> IndexStats {
        let chatDb = try SQLiteDB(path: Paths.chatDB, readonly: true)

        if full {
            try index.exec("DELETE FROM messages; DELETE FROM messages_fts; DELETE FROM chats; DELETE FROM meta;")
        }

        try syncChats(chatDb)

        let watermark = Int64(getMeta("rowid_watermark") ?? "0") ?? 0

        // item_type 0 = actual message; associated_message_type 0 = not a tapback.
        let rows = try chatDb.query(
            """
            SELECT m.ROWID, m.guid, m.text, m.attributedBody, m.is_from_me, m.date,
                   m.service, m.cache_has_attachments,
                   h.id,
                   (SELECT cmj.chat_id FROM chat_message_join cmj WHERE cmj.message_id = m.ROWID LIMIT 1)
            FROM message m
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE m.ROWID > ? AND m.associated_message_type = 0 AND m.item_type = 0
            ORDER BY m.ROWID
            """, [.int(watermark)]
        )

        var indexed = 0
        var maxRowid = watermark
        try index.exec("BEGIN")
        do {
            for row in rows {
                let rowid = row.int(0) ?? 0
                if rowid > maxRowid { maxRowid = rowid }
                let raw = row.text(2) ?? row.blob(3).flatMap(TypedStream.decodeText)
                guard let raw else { continue }
                let text = TypedStream.cleanText(raw)
                guard !text.isEmpty else { continue }

                let isFromMe = row.int(4) == 1
                let sender = row.text(8)
                let senderName = isFromMe ? "Me" : sender.flatMap { contacts.name(for: $0) } ?? sender ?? "Unknown"

                try index.run(
                    """
                    INSERT OR REPLACE INTO messages
                      (rowid, guid, chat_id, sender, sender_name, is_from_me, date_utc, service, has_attachment, text)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .int(rowid), .text(row.text(1) ?? ""),
                        row.int(9).map(SQLiteDB.Value.int) ?? .null,
                        sender.map(SQLiteDB.Value.text) ?? .null,
                        .text(senderName),
                        .int(isFromMe ? 1 : 0),
                        .int(Self.toUnixSeconds(row.int(5) ?? 0)),
                        row.text(6).map(SQLiteDB.Value.text) ?? .null,
                        .int(row.int(7) ?? 0),
                        .text(text),
                    ]
                )
                try index.run("INSERT INTO messages_fts(rowid, text) VALUES (?, ?)", [.int(rowid), .text(text)])
                indexed += 1
            }
            try index.exec("COMMIT")
        } catch {
            try? index.exec("ROLLBACK")
            throw error
        }

        setMeta("rowid_watermark", String(maxRowid))
        setMeta("last_sync", ISO8601DateFormatter().string(from: Date()))

        let total = Int(try index.query("SELECT COUNT(*) FROM messages").first?.int(0) ?? 0)
        return IndexStats(scanned: rows.count, indexed: indexed, total: total)
    }

    private func syncChats(_ chatDb: SQLiteDB) throws {
        let rows = try chatDb.query(
            """
            SELECT c.ROWID, c.chat_identifier, c.display_name, c.style,
                   (SELECT group_concat(h.id, ',') FROM chat_handle_join chj
                    JOIN handle h ON h.ROWID = chj.handle_id WHERE chj.chat_id = c.ROWID),
                   c.properties
            FROM chat c
            """
        )
        for row in rows {
            let isGroup = row.int(3) == 43
            var name = row.text(2)?.trimmingCharacters(in: .whitespaces) ?? ""
            let identifier = row.text(1) ?? ""
            let participants = row.text(4)
            if name.isEmpty, let participants {
                let resolved = participants.split(separator: ",").map { h -> String in
                    let handle = String(h)
                    return contacts.name(for: handle) ?? handle
                }
                name = resolved.prefix(4).joined(separator: ", ") + (resolved.count > 4 ? " +\(resolved.count - 4)" : "")
            }
            if name.isEmpty { name = identifier }

            var photoPath: String?
            if isGroup, let props = row.blob(5) {
                photoPath = try? groupPhotoPath(chatDb, properties: props)
            }

            try index.run(
                """
                INSERT INTO chats(chat_id, identifier, display_name, is_group, photo_path, participants)
                VALUES(?, ?, ?, ?, ?, ?)
                ON CONFLICT(chat_id) DO UPDATE SET identifier = excluded.identifier,
                  display_name = excluded.display_name, is_group = excluded.is_group,
                  photo_path = excluded.photo_path, participants = excluded.participants
                """,
                [
                    .int(row.int(0) ?? 0), .text(identifier), .text(name), .int(isGroup ? 1 : 0),
                    photoPath.map(SQLiteDB.Value.text) ?? .null,
                    participants.map(SQLiteDB.Value.text) ?? .null,
                ]
            )
        }
    }

    /// Custom group photos live behind `groupPhotoGuid` in the chat's
    /// `properties` plist, pointing at an attachment row whose file sits in
    /// ~/Library/Messages/Attachments.
    private func groupPhotoPath(_ chatDb: SQLiteDB, properties: Data) throws -> String? {
        guard let plist = try PropertyListSerialization.propertyList(from: properties, format: nil) as? [String: Any],
              let guid = plist["groupPhotoGuid"] as? String,
              let filename = try chatDb.query(
                  "SELECT filename FROM attachment WHERE guid = ?", [.text(guid)]
              ).first?.text(0)
        else { return nil }
        let expanded = filename.hasPrefix("~") ? Paths.home + filename.dropFirst() : filename
        return FileManager.default.fileExists(atPath: expanded) ? expanded : nil
    }

    private func getMeta(_ key: String) -> String? {
        try? index.query("SELECT value FROM meta WHERE key = ?", [.text(key)]).first?.text(0)
    }

    private func setMeta(_ key: String, _ value: String) {
        try? index.run(
            "INSERT INTO meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            [.text(key), .text(value)]
        )
    }

    // MARK: - Search

    /// Each token becomes a quoted prefix term ("tok"*) — as-you-type friendly
    /// and immune to FTS syntax injection.
    private static func ftsQuery(_ input: String) -> String? {
        let tokens = input.split(whereSeparator: \.isWhitespace)
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    func search(query: String, filters: SearchFilters = SearchFilters(), limit: Int = 50, offset: Int = 0) throws -> SearchResult {
        let started = DispatchTime.now()
        guard let fts = Self.ftsQuery(query) else { return SearchResult(hits: [], total: 0, millis: 0) }

        var conditions = ["messages_fts MATCH ?"]
        var params: [SQLiteDB.Value] = [.text(fts)]

        if !filters.from.isEmpty {
            conditions.append("(m.sender_name LIKE ? OR m.sender LIKE ?)")
            params.append(.text("%\(filters.from)%"))
            params.append(.text("%\(filters.from)%"))
        }
        if !filters.chat.isEmpty {
            conditions.append("(c.display_name LIKE ? OR c.identifier LIKE ?)")
            params.append(.text("%\(filters.chat)%"))
            params.append(.text("%\(filters.chat)%"))
        }
        if !filters.chatIds.isEmpty {
            conditions.append("m.chat_id IN (\(filters.chatIds.map { _ in "?" }.joined(separator: ",")))")
            params.append(contentsOf: filters.chatIds.map(SQLiteDB.Value.int))
        }
        if let after = filters.after {
            conditions.append("m.date_utc >= ?")
            params.append(.int(Int64(after.timeIntervalSince1970)))
        }
        if let before = filters.before {
            conditions.append("m.date_utc < ?")
            params.append(.int(Int64(before.timeIntervalSince1970)))
        }

        let base = """
            FROM messages_fts
            JOIN messages m ON m.rowid = messages_fts.rowid
            LEFT JOIN chats c ON c.chat_id = m.chat_id
            WHERE \(conditions.joined(separator: " AND "))
            """
        let total = Int(try index.query("SELECT COUNT(*) \(base)", params).first?.int(0) ?? 0)

        let order = filters.sortByRelevance ? "ORDER BY rank" : "ORDER BY m.date_utc DESC"
        let hits = try index.query(
            "SELECT \(Self.messageColumns) \(base) \(order) LIMIT ? OFFSET ?",
            params + [.int(Int64(min(limit, 200))), .int(Int64(offset))]
        ).map(Self.toMessage)

        let millis = Int(Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e6)
        return SearchResult(hits: hits, total: total, millis: millis)
    }

    private static let messageColumns = """
        m.rowid, m.guid, m.chat_id, c.display_name, COALESCE(c.is_group, 0),
        m.sender, m.sender_name, m.is_from_me, m.date_utc, m.service, m.has_attachment, m.text
        """

    private static func toMessage(_ row: SQLiteDB.Row) -> Message {
        Message(
            rowid: row.int(0) ?? 0,
            guid: row.text(1) ?? "",
            chatId: row.int(2),
            chatName: row.text(3),
            isGroup: row.int(4) == 1,
            sender: row.text(5),
            senderName: row.text(6) ?? "Unknown",
            isFromMe: row.int(7) == 1,
            date: Date(timeIntervalSince1970: TimeInterval(row.int(8) ?? 0)),
            service: row.text(9),
            hasAttachment: row.int(10) == 1,
            text: row.text(11) ?? ""
        )
    }

    // MARK: - Live thread views
    //
    // Threads read straight from chat.db at render time (search stays on the
    // text-only FTS index). This makes attachment-only messages, tapbacks,
    // and reply links visible without indexing any of them — enrichment only
    // touches the ~80 rows on screen.

    private var chatView: SQLiteDB?

    private func liveDb() throws -> SQLiteDB {
        if let chatView { return chatView }
        let db = try SQLiteDB(path: Paths.chatDB, readonly: true)
        chatView = db
        return db
    }

    private static func toAppleNs(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 - appleEpoch) * 1e9)
    }

    private lazy var hasEmojiColumn: Bool = {
        (try? liveDb().query("SELECT associated_message_emoji FROM message LIMIT 1")) != nil
    }()

    /// Messages around a point in a conversation (multiple chat ids because
    /// same-person SMS and iMessage chats merge into one conversation).
    func contextMessages(chatIds: [Int64], around date: Date, radius: Int = 25) throws -> [Message] {
        guard !chatIds.isEmpty else { return [] }
        if isDemoConversation(chatIds) {
            let ts = Int64(date.timeIntervalSince1970)
            let before = try demoMessages(cond: "AND m.date_utc <= ?", params: [.int(ts)],
                                          descending: true, limit: radius + 1)
            let after = try demoMessages(cond: "AND m.date_utc > ?", params: [.int(ts)],
                                         descending: false, limit: radius)
            var messages = Array(before.reversed()) + after
            try demoEnrich(&messages)
            return messages
        }
        let ns = Self.toAppleNs(date)
        let before = try liveMessages(chatIds: chatIds, cond: "AND m.date <= ?",
                                      condParams: [.int(ns)], descending: true, limit: radius + 1)
        let after = try liveMessages(chatIds: chatIds, cond: "AND m.date > ?",
                                     condParams: [.int(ns)], descending: false, limit: radius)
        var messages = Array(before.reversed()) + after
        try enrich(&messages)
        return messages
    }

    /// Most recent messages of a conversation, oldest-first.
    func recentMessages(chatIds: [Int64], before: Date? = nil, limit: Int = 60) throws -> [Message] {
        guard !chatIds.isEmpty else { return [] }
        if isDemoConversation(chatIds) {
            var cond = ""
            var params: [SQLiteDB.Value] = []
            if let before {
                cond = "AND m.date_utc < ?"
                params.append(.int(Int64(before.timeIntervalSince1970)))
            }
            var messages = Array(try demoMessages(cond: cond, params: params,
                                                  descending: true, limit: limit).reversed())
            try demoEnrich(&messages)
            return messages
        }
        var cond = ""
        var condParams: [SQLiteDB.Value] = []
        if let before {
            cond = "AND m.date < ?"
            condParams.append(.int(Self.toAppleNs(before)))
        }
        var messages = Array(try liveMessages(chatIds: chatIds, cond: cond, condParams: condParams,
                                              descending: true, limit: limit).reversed())
        try enrich(&messages)
        return messages
    }

    private func liveMessages(chatIds: [Int64], cond: String, condParams: [SQLiteDB.Value],
                              descending: Bool, limit: Int) throws -> [Message] {
        let db = try liveDb()
        let inClause = chatIds.map { _ in "?" }.joined(separator: ",")
        let rows = try db.query(
            """
            SELECT m.ROWID, m.guid, m.text, m.attributedBody, m.is_from_me, m.date,
                   m.service, m.cache_has_attachments, h.id, cmj.chat_id, m.thread_originator_guid,
                   m.balloon_bundle_id, m.payload_data
            FROM chat_message_join cmj
            JOIN message m ON m.ROWID = cmj.message_id
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE cmj.chat_id IN (\(inClause))
              AND m.item_type = 0 AND m.associated_message_type = 0 \(cond)
            ORDER BY m.date \(descending ? "DESC" : "ASC") LIMIT ?
            """,
            chatIds.map(SQLiteDB.Value.int) + condParams + [.int(Int64(limit))]
        )
        return rows.map { row in
            let raw = row.text(2) ?? row.blob(3).flatMap(TypedStream.decodeText)
            let isFromMe = row.int(4) == 1
            let sender = row.text(8)
            var m = Message(
                rowid: row.int(0) ?? 0,
                guid: row.text(1) ?? "",
                chatId: row.int(9),
                chatName: nil,
                isGroup: false,
                sender: sender,
                senderName: isFromMe ? "Me" : sender.flatMap { contacts.name(for: $0) } ?? sender ?? "Unknown",
                isFromMe: isFromMe,
                date: Date(timeIntervalSince1970: Double(Self.toUnixSeconds(row.int(5) ?? 0))),
                service: row.text(6),
                hasAttachment: row.int(7) == 1,
                text: raw.map(TypedStream.cleanText) ?? ""
            )
            m.replyTo = row.text(10).map { ReplyPreview(senderName: $0, text: "") } // guid stashed, resolved in enrich
            if row.text(11) == "com.apple.messages.URLBalloonProvider" {
                m.linkPreview = row.blob(12).flatMap(RichLink.parse)
                    ?? (m.text.hasPrefix("http") ? LinkPreview(url: m.text, title: nil, site: nil) : nil)
            }
            return m
        }
    }

    /// Attach images/videos, tapback badges, and reply previews to the given
    /// (small) window of messages via live chat.db lookups.
    private func enrich(_ messages: inout [Message]) throws {
        guard !messages.isEmpty else { return }
        let db = try liveDb()

        // Attachments
        let withAttachments = messages.enumerated().filter { $0.element.hasAttachment }
        if !withAttachments.isEmpty {
            let ids = withAttachments.map(\.element.rowid)
            let inClause = ids.map { _ in "?" }.joined(separator: ",")
            let rows = try db.query(
                """
                SELECT maj.message_id, a.filename, a.mime_type, a.uti
                FROM message_attachment_join maj JOIN attachment a ON a.ROWID = maj.attachment_id
                WHERE maj.message_id IN (\(inClause)) AND a.filename IS NOT NULL
                """, ids.map(SQLiteDB.Value.int)
            )
            var byMessage: [Int64: [MsgAttachment]] = [:]
            for row in rows {
                guard let att = Self.makeAttachment(filename: row.text(1), mime: row.text(2), uti: row.text(3)) else { continue }
                byMessage[row.int(0) ?? 0, default: []].append(att)
            }
            for (i, m) in withAttachments {
                messages[i].attachments = byMessage[m.rowid] ?? []
            }
        }

        // Tapbacks: reaction rows in the same chats, from the window start on
        // (reactions land after their target message).
        if let chatId = messages.first?.chatId {
            let chatIds = Set(messages.compactMap(\.chatId)).union([chatId])
            let inClause = chatIds.map { _ in "?" }.joined(separator: ",")
            let minDate = Self.toAppleNs(messages.first!.date)
            let emojiCol = hasEmojiColumn ? ", m.associated_message_emoji" : ""
            let rows = try db.query(
                """
                SELECT m.associated_message_guid, m.associated_message_type, m.is_from_me, h.id\(emojiCol)
                FROM chat_message_join cmj
                JOIN message m ON m.ROWID = cmj.message_id
                LEFT JOIN handle h ON h.ROWID = m.handle_id
                WHERE cmj.chat_id IN (\(inClause))
                  AND m.associated_message_type BETWEEN 2000 AND 3999 AND m.date >= ?
                ORDER BY m.ROWID
                """, chatIds.map(SQLiteDB.Value.int) + [.int(minDate)]
            )
            let guids = Set(messages.map(\.guid))
            var perMessage: [String: [String: (kind: Int, custom: String?)]] = [:] // guid → senderKey → reaction
            for row in rows {
                guard let target = Self.stripAssociatedGuid(row.text(0)), guids.contains(target) else { continue }
                let kind = Int(row.int(1) ?? 0)
                let senderKey = row.int(2) == 1 ? "me" : (row.text(3) ?? "?")
                if kind >= 3000 {
                    perMessage[target]?.removeValue(forKey: senderKey)
                } else {
                    let custom = hasEmojiColumn ? row.text(4) : nil
                    perMessage[target, default: [:]][senderKey] = (kind, custom)
                }
            }
            for i in messages.indices {
                guard let senders = perMessage[messages[i].guid], !senders.isEmpty else { continue }
                struct Key: Hashable {
                    let kind: Int
                    let custom: String?
                }
                var groups: [Key: [String]] = [:] // reaction → reactor display names
                for (senderKey, reaction) in senders {
                    let name = senderKey == "me" ? "Me" : (contacts.name(for: senderKey) ?? senderKey)
                    groups[Key(kind: reaction.kind, custom: reaction.custom), default: []].append(name)
                }
                messages[i].reactions = groups
                    .map { key, names in
                        ReactionBadge(
                            kind: key.kind,
                            custom: key.custom,
                            reactors: names.sorted { $0 == "Me" ? true : ($1 == "Me" ? false : $0 < $1) },
                            fromMe: names.contains("Me")
                        )
                    }
                    .sorted { $0.count > $1.count }
            }
        }

        // Reply previews: liveMessages stashed the parent guid in replyTo.senderName
        // (with empty text) — resolve those into real sender/text pairs.
        let pending = messages.enumerated().compactMap { (i, m) -> (Int, String)? in
            guard let stash = m.replyTo, stash.text.isEmpty, !stash.senderName.isEmpty else { return nil }
            return (i, stash.senderName)
        }
        if !pending.isEmpty {
            let guidList = Set(pending.map(\.1))
            let inClause = guidList.map { _ in "?" }.joined(separator: ",")
            let rows = try db.query(
                """
                SELECT m.guid, m.text, m.attributedBody, m.is_from_me, h.id, m.ROWID, m.date
                FROM message m LEFT JOIN handle h ON h.ROWID = m.handle_id
                WHERE m.guid IN (\(inClause))
                """, guidList.map(SQLiteDB.Value.text)
            )
            var parents: [String: ReplyPreview] = [:]
            for row in rows {
                let raw = row.text(1) ?? row.blob(2).flatMap(TypedStream.decodeText)
                var text = raw.map(TypedStream.cleanText) ?? ""
                if text.isEmpty { text = "Attachment" }
                if text.count > 80 { text = String(text.prefix(80)) + "…" }
                let name = row.int(3) == 1 ? "Me" : row.text(4).flatMap { contacts.name(for: $0) } ?? row.text(4) ?? "?"
                parents[row.text(0) ?? ""] = ReplyPreview(
                    senderName: name,
                    text: text,
                    rowid: row.int(5),
                    date: Date(timeIntervalSince1970: Double(Self.toUnixSeconds(row.int(6) ?? 0)))
                )
            }
            for (i, guid) in pending {
                messages[i].replyTo = parents[guid]
            }
        }
    }

    private static func stripAssociatedGuid(_ raw: String?) -> String? {
        guard var g = raw else { return nil }
        if let slash = g.firstIndex(of: "/") { g = String(g[g.index(after: slash)...]) }
        if g.hasPrefix("bp:") { g = String(g.dropFirst(3)) }
        return g.isEmpty ? nil : g
    }

    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp"]
    private static let videoExts: Set<String> = ["mov", "mp4", "m4v", "avi"]

    private static func makeAttachment(filename: String?, mime: String?, uti: String?) -> MsgAttachment? {
        guard let filename else { return nil }
        // Rich-link metadata payloads are not user media — rendered as link cards.
        guard !filename.hasSuffix(".pluginPayloadAttachment") else { return nil }
        let path = filename.hasPrefix("~") ? Paths.home + filename.dropFirst() : filename
        let ext = (path as NSString).pathExtension.lowercased()
        let isImage = mime?.hasPrefix("image/") ?? imageExts.contains(ext)
        let isVideo = mime?.hasPrefix("video/") ?? videoExts.contains(ext)
        return MsgAttachment(path: path, mime: mime, isImage: isImage, isVideo: isVideo)
    }

    /// All image/video attachments of a conversation, newest first — the
    /// media gallery. Live from chat.db; nothing is indexed.
    func mediaItems(chatIds: [Int64], limit: Int = 300) throws -> [MediaItem] {
        guard !chatIds.isEmpty else { return [] }
        if isDemoConversation(chatIds) { return [] } // demo has no media
        let db = try liveDb()
        let inClause = chatIds.map { _ in "?" }.joined(separator: ",")
        let rows = try db.query(
            """
            SELECT a.filename, a.mime_type, a.uti, cmj.message_id, m.date
            FROM chat_message_join cmj
            JOIN message_attachment_join maj ON maj.message_id = cmj.message_id
            JOIN attachment a ON a.ROWID = maj.attachment_id
            JOIN message m ON m.ROWID = cmj.message_id
            WHERE cmj.chat_id IN (\(inClause)) AND a.filename IS NOT NULL
            ORDER BY m.date DESC LIMIT ?
            """, chatIds.map(SQLiteDB.Value.int) + [.int(Int64(limit * 2))]
        )
        var items: [MediaItem] = []
        for row in rows {
            guard let att = Self.makeAttachment(filename: row.text(0), mime: row.text(1), uti: row.text(2)),
                  att.isImage || att.isVideo,
                  FileManager.default.fileExists(atPath: att.path) else { continue }
            items.append(MediaItem(
                path: att.path,
                date: Date(timeIntervalSince1970: Double(Self.toUnixSeconds(row.int(4) ?? 0))),
                messageRowid: row.int(3) ?? 0,
                isVideo: att.isVideo
            ))
            if items.count >= limit { break }
        }
        return items
    }

    /// iMessage-style conversation list: DM chats merged across services by contact.
    func conversations() throws -> [Conversation] {
        let rows = try index.query(
            """
            SELECT m.chat_id, c.identifier, c.display_name, COALESCE(c.is_group, 0),
                   MAX(m.date_utc), COUNT(*), c.photo_path, c.participants
            FROM messages m JOIN chats c ON c.chat_id = m.chat_id
            GROUP BY m.chat_id
            """
        )

        var merged: [String: Conversation] = [:]
        for row in rows {
            let chatId = row.int(0) ?? 0
            let identifier = row.text(1) ?? ""
            let isGroup = row.int(3) == 1
            let lastDate = Date(timeIntervalSince1970: TimeInterval(row.int(4) ?? 0))
            let count = Int(row.int(5) ?? 0)
            let key = isGroup ? "chat:\(chatId)" : "dm:\(ContactsStore.handleKey(identifier))"
            let participants: [Participant] = (row.text(7) ?? "").split(separator: ",").prefix(4).map {
                let handle = String($0)
                return Participant(handle: handle, name: contacts.name(for: handle) ?? handle)
            }

            if var existing = merged[key] {
                existing.chatIds.append(chatId)
                existing.count += count
                if lastDate > existing.lastDate {
                    existing.lastDate = lastDate
                    existing.name = row.text(2) ?? identifier
                    existing.handle = isGroup ? nil : identifier
                }
                merged[key] = existing
            } else {
                merged[key] = Conversation(
                    key: key,
                    name: row.text(2) ?? identifier,
                    chatIds: [chatId],
                    isGroup: isGroup,
                    handle: isGroup ? nil : identifier,
                    lastDate: lastDate,
                    count: count,
                    previewText: nil,
                    previewFromMe: false,
                    previewSender: nil,
                    hasAvatar: false,
                    groupPhotoPath: row.text(6),
                    participants: participants
                )
            }
        }

        var list = merged.values.sorted { $0.lastDate > $1.lastDate }
        for i in list.indices {
            let inClause = list[i].chatIds.map { _ in "?" }.joined(separator: ",")
            if let p = try? index.query(
                "SELECT text, is_from_me, sender_name FROM messages WHERE chat_id IN (\(inClause)) ORDER BY date_utc DESC LIMIT 1",
                list[i].chatIds.map(SQLiteDB.Value.int)
            ).first {
                list[i].previewText = p.text(0)
                list[i].previewFromMe = p.int(1) == 1
                list[i].previewSender = p.text(2)
            }
            if let handle = list[i].handle {
                list[i].hasAvatar = contacts.hasAvatar(handle: handle, name: list[i].name)
            }
        }
        return list
    }

    func avatarData(handle: String, name: String?) -> Data? {
        contacts.avatarData(handle: handle, name: name)
    }

    func hasAvatar(handle: String, name: String?) -> Bool {
        contacts.hasAvatar(handle: handle, name: name)
    }

    /// Distinct sender names ranked by message volume — autocomplete pool
    /// for the "From" filter.
    func senderNames(limit: Int = 3000) throws -> [String] {
        try index.query(
            """
            SELECT sender_name FROM messages
            WHERE is_from_me = 0 AND sender_name IS NOT NULL AND sender_name != ''
            GROUP BY sender_name ORDER BY COUNT(*) DESC LIMIT ?
            """, [.int(Int64(limit))]
        ).compactMap { $0.text(0) }
    }

    func totalIndexed() throws -> Int {
        Int(try index.query("SELECT COUNT(*) FROM messages").first?.int(0) ?? 0)
    }

    // MARK: - Demo conversation
    //
    // A synthetic conversation for screen recordings, stored ONLY in the
    // index database (plus two small side tables for tapbacks and reply
    // quotes). chat.db is never written. The chat id and rowids sit at
    // 9_000_000_000+, far beyond anything a real chat.db reaches, so the
    // incremental sync watermark and INSERT OR REPLACE upserts (both driven
    // purely by chat.db rowids) can never collide with demo rows. A `full:`
    // re-index wipes demo data along with everything else — just re-seed.

    static let demoChatId: Int64 = 9_000_000_000
    private static let demoRowidBase: Int64 = 9_000_000_000

    private func isDemoConversation(_ chatIds: [Int64]) -> Bool {
        chatIds.contains(Self.demoChatId)
    }

    func seedDemoConversation() throws {
        try removeDemoConversation()
        try index.exec(
            """
            CREATE TABLE IF NOT EXISTS demo_reactions (
              message_rowid INTEGER NOT NULL, kind INTEGER NOT NULL, reactor TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS demo_replies (
              message_rowid INTEGER PRIMARY KEY, parent_rowid INTEGER NOT NULL);
            """
        )
        let seeds = DemoSeeder.build()
        try index.exec("BEGIN")
        do {
            try index.run(
                """
                INSERT INTO chats(chat_id, identifier, display_name, is_group, photo_path, participants)
                VALUES(?, ?, ?, 0, NULL, ?)
                ON CONFLICT(chat_id) DO UPDATE SET identifier = excluded.identifier,
                  display_name = excluded.display_name
                """,
                [.int(Self.demoChatId), .text(DemoSeeder.handle),
                 .text(DemoSeeder.displayName), .text(DemoSeeder.handle)]
            )
            for (i, seed) in seeds.enumerated() {
                let rowid = Self.demoRowidBase + Int64(i)
                try index.run(
                    """
                    INSERT INTO messages
                      (rowid, guid, chat_id, sender, sender_name, is_from_me, date_utc, service, has_attachment, text)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 'iMessage', 0, ?)
                    """,
                    [
                        .int(rowid), .text("demo-msg-\(i)"), .int(Self.demoChatId),
                        seed.fromMe ? .null : .text(DemoSeeder.handle),
                        .text(seed.fromMe ? "Me" : DemoSeeder.displayName),
                        .int(seed.fromMe ? 1 : 0),
                        .int(Int64(seed.date.timeIntervalSince1970)),
                        .text(seed.text),
                    ]
                )
                try index.run("INSERT INTO messages_fts(rowid, text) VALUES (?, ?)",
                              [.int(rowid), .text(seed.text)])
                if let kind = seed.react {
                    // The tapback comes from whoever did NOT write the message.
                    let reactor = seed.fromMe ? DemoSeeder.displayName : "Me"
                    try index.run("INSERT INTO demo_reactions(message_rowid, kind, reactor) VALUES (?, ?, ?)",
                                  [.int(rowid), .int(Int64(kind)), .text(reactor)])
                }
                if let back = seed.replyBack, i - back >= 0 {
                    try index.run("INSERT INTO demo_replies(message_rowid, parent_rowid) VALUES (?, ?)",
                                  [.int(rowid), .int(Self.demoRowidBase + Int64(i - back))])
                }
            }
            try index.exec("COMMIT")
        } catch {
            try? index.exec("ROLLBACK")
            throw error
        }
    }

    func removeDemoConversation() throws {
        let rows = try index.query("SELECT rowid, text FROM messages WHERE chat_id = ?",
                                   [.int(Self.demoChatId)])
        try index.exec("BEGIN")
        do {
            for row in rows {
                // External-content FTS5: deletions must be mirrored explicitly.
                try index.run("INSERT INTO messages_fts(messages_fts, rowid, text) VALUES ('delete', ?, ?)",
                              [.int(row.int(0) ?? 0), .text(row.text(1) ?? "")])
            }
            try index.run("DELETE FROM messages WHERE chat_id = ?", [.int(Self.demoChatId)])
            try index.run("DELETE FROM chats WHERE chat_id = ?", [.int(Self.demoChatId)])
            try? index.exec("DELETE FROM demo_reactions; DELETE FROM demo_replies;")
            try index.exec("COMMIT")
        } catch {
            try? index.exec("ROLLBACK")
            throw error
        }
    }

    /// Thread reads for the demo conversation come from the index (the demo
    /// has no chat.db rows). Mirrors liveMessages + enrich.
    private func demoMessages(cond: String, params: [SQLiteDB.Value],
                              descending: Bool, limit: Int) throws -> [Message] {
        let rows = try index.query(
            """
            SELECT m.rowid, m.guid, m.sender, m.sender_name, m.is_from_me, m.date_utc, m.service, m.text
            FROM messages m
            WHERE m.chat_id = \(Self.demoChatId) \(cond)
            ORDER BY m.date_utc \(descending ? "DESC" : "ASC"), m.rowid \(descending ? "DESC" : "ASC")
            LIMIT ?
            """, params + [.int(Int64(limit))]
        )
        return rows.map { row in
            Message(
                rowid: row.int(0) ?? 0,
                guid: row.text(1) ?? "",
                chatId: Self.demoChatId,
                chatName: DemoSeeder.displayName,
                isGroup: false,
                sender: row.text(2),
                senderName: row.text(3) ?? "Unknown",
                isFromMe: row.int(4) == 1,
                date: Date(timeIntervalSince1970: TimeInterval(row.int(5) ?? 0)),
                service: row.text(6),
                hasAttachment: false,
                text: row.text(7) ?? ""
            )
        }
    }

    private func demoEnrich(_ messages: inout [Message]) throws {
        guard !messages.isEmpty else { return }
        let ids = messages.map(\.rowid)
        let inClause = ids.map { _ in "?" }.joined(separator: ",")
        let byRowid = Dictionary(uniqueKeysWithValues: messages.enumerated().map { ($1.rowid, $0) })

        let reactions = try index.query(
            "SELECT message_rowid, kind, reactor FROM demo_reactions WHERE message_rowid IN (\(inClause))",
            ids.map(SQLiteDB.Value.int)
        )
        var badges: [Int64: [ReactionBadge]] = [:]
        for row in reactions {
            let reactor = row.text(2) ?? "?"
            badges[row.int(0) ?? 0, default: []].append(ReactionBadge(
                kind: Int(row.int(1) ?? 0), custom: nil,
                reactors: [reactor], fromMe: reactor == "Me"
            ))
        }
        for (rowid, list) in badges {
            if let i = byRowid[rowid] { messages[i].reactions = list }
        }

        let replies = try index.query(
            """
            SELECT r.message_rowid, p.sender_name, p.text, p.rowid, p.date_utc
            FROM demo_replies r JOIN messages p ON p.rowid = r.parent_rowid
            WHERE r.message_rowid IN (\(inClause))
            """, ids.map(SQLiteDB.Value.int)
        )
        for row in replies {
            guard let i = byRowid[row.int(0) ?? 0] else { continue }
            var text = row.text(2) ?? ""
            if text.count > 80 { text = String(text.prefix(80)) + "…" }
            messages[i].replyTo = ReplyPreview(
                senderName: row.text(1) ?? "?", text: text, rowid: row.int(3),
                date: Date(timeIntervalSince1970: TimeInterval(row.int(4) ?? 0))
            )
        }
    }

    /// First/last message dates of a conversation (bounds for jump-to-date).
    func dateRange(chatIds: [Int64]) throws -> ClosedRange<Date>? {
        guard !chatIds.isEmpty else { return nil }
        let inClause = chatIds.map { _ in "?" }.joined(separator: ",")
        guard let row = try index.query(
            "SELECT MIN(date_utc), MAX(date_utc) FROM messages WHERE chat_id IN (\(inClause))",
            chatIds.map(SQLiteDB.Value.int)
        ).first, let lo = row.int(0), let hi = row.int(1) else { return nil }
        return Date(timeIntervalSince1970: Double(lo))...Date(timeIntervalSince1970: Double(hi))
    }
}
