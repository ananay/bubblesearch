import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    let engine: Engine
    private var watcher: ChatDBWatcher?

    enum Tab {
        case chats, advanced
    }

    @Published var tab: Tab = .chats

    // Sidebar
    @Published var conversations: [Conversation] = []
    @Published var selectedKey: String?
    @Published var convoFilter = ""
    @Published var totalIndexed = 0

    /// Conversations whose preview text is hidden in the sidebar, by
    /// conversation key. Initialized synchronously from UserDefaults — the
    /// store exists before the first render, so a hidden preview can never
    /// flash on screen while the app starts.
    private static let hiddenPreviewsDefaultsKey = "hiddenPreviewKeys"
    @Published private(set) var hiddenPreviewKeys: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: hiddenPreviewsDefaultsKey) ?? [])

    func setPreviewHidden(_ hidden: Bool, for conversationKey: String) {
        if hidden {
            hiddenPreviewKeys.insert(conversationKey)
        } else {
            hiddenPreviewKeys.remove(conversationKey)
        }
        UserDefaults.standard.set(
            Array(hiddenPreviewKeys).sorted(),
            forKey: Self.hiddenPreviewsDefaultsKey
        )
    }

    var filteredConversations: [Conversation] {
        let f = convoFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !f.isEmpty else { return conversations }
        return conversations.filter {
            $0.name.lowercased().contains(f) || ($0.handle?.lowercased().contains(f) ?? false)
        }
    }

    // Advanced search (its own tab on the rail)
    @Published var globalQuery = ""
    @Published var globalResults: [Message] = []
    @Published var globalTotal = 0
    @Published var globalMillis = 0
    @Published var filters = SearchFilters()
    @Published var advSelectedHit: Message?
    @Published var advContext: [Message] = []
    @Published var showFilterSidebar = false
    @Published var senderSuggestions: [String] = []

    /// Chat-name pool for the "In chat" filter, already in recency order.
    var chatSuggestions: [String] {
        var seen = Set<String>()
        return conversations.compactMap { seen.insert($0.name).inserted ? $0.name : nil }
    }

    /// Rank suggestions: prefix matches first, then substring matches.
    func suggest(_ query: String, from pool: [String], limit: Int = 6) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var prefixMatches: [String] = []
        var containsMatches: [String] = []
        for name in pool {
            let lower = name.lowercased()
            if lower == q { continue } // already typed exactly
            if lower.hasPrefix(q) {
                prefixMatches.append(name)
            } else if lower.contains(q) {
                containsMatches.append(name)
            }
            if prefixMatches.count >= limit { break }
        }
        return Array((prefixMatches + containsMatches).prefix(limit))
    }

    // Thread / in-conversation search.
    // `thread` is the raw message window; `threadRows` is the render-ready
    // list (day separators + sender-label grouping), precomputed ONCE per
    // mutation instead of on every SwiftUI render pass.
    struct ThreadRow: Identifiable {
        enum Kind {
            case daySeparator(Date)
            case message(Message, showLabel: Bool)
        }

        let id: Int64 // message rowid; day separators use negative day ordinals
        let kind: Kind
    }

    private(set) var thread: [Message] = []
    @Published private(set) var threadRows: [ThreadRow] = []
    private(set) var topTriggerRowid: Int64? // onAppear of this row prefetches older

    /// Assign the thread window and rebuild render rows.
    private func setThread(_ messages: [Message]) {
        thread = messages
        var rows: [ThreadRow] = []
        rows.reserveCapacity(messages.count + 64)
        var lastDay = Int.min
        var lastSender: String?
        var lastDate: Date?
        let cal = Calendar.current
        for m in messages {
            let day = cal.ordinality(of: .day, in: .era, for: m.date) ?? 0
            if day != lastDay {
                rows.append(ThreadRow(id: Int64(-day), kind: .daySeparator(m.date)))
                lastDay = day
                lastSender = nil
            }
            let senderKey = m.isFromMe ? "me" : (m.sender ?? m.senderName)
            let gap = lastDate.map { m.date.timeIntervalSince($0) > 3600 } ?? true
            rows.append(ThreadRow(id: m.rowid, kind: .message(m, showLabel: senderKey != lastSender || gap)))
            lastSender = senderKey
            lastDate = m.date
        }
        threadRows = rows
        let messageIds = messages.map(\.rowid)
        topTriggerRowid = messageIds.count > 12 ? messageIds[8] : messageIds.first
    }

    @Published var anchorRowid: Int64?
    @Published var convoQuery = ""
    @Published var convoResults: [Message] = []
    @Published var convoTotal = 0
    @Published var canLoadOlder = true
    @Published var isLoadingOlder = false

    // Scroll commands: views act when scrollTick changes.
    enum ScrollTarget: Equatable {
        case bottom
        case message(Int64)
    }

    @Published var scrollTarget: ScrollTarget = .bottom
    @Published var scrollTick = 0

    private func requestScroll(_ target: ScrollTarget) {
        scrollTarget = target
        scrollTick += 1
    }

    // Media gallery
    @Published var showMedia = false
    @Published var mediaItems: [MediaItem] = []

    // ⌘F: focus the in-conversation search field
    @Published var convoSearchFocusTick = 0

    func focusConvoSearch() {
        guard selectedConversation != nil else { return }
        tab = .chats
        showMedia = false
        convoSearchFocusTick += 1
    }

    // ⌘K: quick-search palette
    @Published var showPalette = false {
        didSet {
            if !showPalette {
                paletteQuery = ""
                paletteResults = []
                paletteIndex = 0
            }
        }
    }

    @Published var paletteQuery = ""
    @Published var paletteResults: [Message] = [] // messages, below people
    @Published var paletteIndex = 0

    /// People matches, COMPUTED from the live query on every render — can
    /// never go stale, only conversations whose name (or handle) actually
    /// matches appear. Prefix matches rank first; recency order within.
    var paletteConvos: [Conversation] {
        let query = paletteQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        var prefixMatches: [Conversation] = []
        var containsMatches: [Conversation] = []
        for convo in conversations {
            let name = convo.name.lowercased()
            if name.hasPrefix(query) {
                prefixMatches.append(convo)
                if prefixMatches.count >= 5 { break }
            } else if containsMatches.count < 5,
                      name.contains(query) || (convo.handle?.lowercased().contains(query) ?? false) {
                containsMatches.append(convo)
            }
        }
        return Array((prefixMatches + containsMatches).prefix(5))
    }

    private var paletteCount: Int { paletteConvos.count + paletteResults.count }

    /// Stable scroll/identity id of the selected palette row ("p-…" / "m-…").
    var paletteScrollID: String? {
        let convos = paletteConvos
        if paletteIndex < convos.count {
            return "p-\(convos[paletteIndex].key)"
        }
        let messageIndex = paletteIndex - convos.count
        guard paletteResults.indices.contains(messageIndex) else { return nil }
        return "m-\(paletteResults[messageIndex].rowid)"
    }

    /// Message search, restarted by the view's .task(id: paletteQuery) —
    /// structured concurrency handles the cancellation, no manual bookkeeping.
    func runPaletteSearch() async {
        paletteIndex = 0
        let query = paletteQuery
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            paletteResults = []
            return
        }
        try? await Task.sleep(nanoseconds: 100_000_000) // debounce
        guard !Task.isCancelled else { return }
        guard let result = try? await engine.search(query: query, limit: 40) else { return }
        guard !Task.isCancelled, query == paletteQuery else { return }
        paletteResults = result.hits
    }

    func movePaletteSelection(_ delta: Int) {
        guard paletteCount > 0 else { return }
        paletteIndex = min(max(paletteIndex + delta, 0), paletteCount - 1)
    }

    func openPaletteSelection() {
        if paletteIndex < paletteConvos.count {
            let convo = paletteConvos[paletteIndex]
            showPalette = false
            openConversation(convo)
        } else {
            let messageIndex = paletteIndex - paletteConvos.count
            guard paletteResults.indices.contains(messageIndex) else { return }
            let hit = paletteResults[messageIndex]
            showPalette = false
            open(hit: hit)
        }
    }

    /// Open a conversation directly (palette person selection).
    func openConversation(_ convo: Conversation) {
        tab = .chats
        lastHandledKey = convo.key
        selectedKey = convo.key
        convoQuery = ""
        convoResults = []
        anchorRowid = nil
        showMedia = false
        Task { await loadThread() }
    }

    // Image caches live in a separate store so loading thumbnails/avatars
    // never re-invalidates the thread structure (major scroll-perf win).
    let media: MediaStore

    @Published var startupError: String?
    @Published var isRefreshing = false
    @Published var needsFullDiskAccess = false
    @Published var isInitialIndexing = false

    /// The real FDA test: can we actually read the Messages database?
    nonisolated static func canReadChatDB() -> Bool {
        guard let handle = FileHandle(forReadingAtPath: Paths.chatDB) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 16)) != nil
    }

    var selectedConversation: Conversation? {
        selectedKey.flatMap { key in conversations.first { $0.key == key } }
    }

    private var globalSearchTask: Task<Void, Never>?
    private var convoSearchTask: Task<Void, Never>?

    init() {
        do {
            engine = try Engine()
        } catch {
            fatalError("BubbleSearch could not open its databases: \(error)\nGrant Full Disk Access or launch from a terminal that has it.")
        }
        media = MediaStore(engine: engine)
        // Before any UI reads the crash-reports toggle: carry an existing
        // telemetry opt-out over to the (newly separate) crash setting.
        CrashReporter.migrateSettingIfNeeded()
        Task { await self.bootstrap() }
    }

    private func bootstrap() async {
        Telemetry.pingIfNeeded()
        CrashReporter.reportNewCrashesIfEnabled()

        // First-run gate: without Full Disk Access, show onboarding and poll
        // until the grant appears (macOS applies it without relaunch often
        // enough that this feels magic when it works).
        if !Self.canReadChatDB() {
            needsFullDiskAccess = true
            while !Self.canReadChatDB() {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            needsFullDiskAccess = false
        }

        do {
            totalIndexed = try await engine.totalIndexed()
            if totalIndexed == 0 { isInitialIndexing = true } // first launch: full build
            conversations = try await engine.conversations()
            senderSuggestions = (try? await engine.senderNames()) ?? []
            let stats = try await engine.syncIndex() // startup catch-up (or first full build)
            if stats.indexed > 0 {
                totalIndexed = stats.total
                conversations = try await engine.conversations()
                senderSuggestions = (try? await engine.senderNames()) ?? senderSuggestions
            }
            isInitialIndexing = false
        } catch {
            isInitialIndexing = false
            startupError = """
                Could not read the Messages database. BubbleSearch needs Full Disk Access: \
                System Settings → Privacy & Security → Full Disk Access → enable BubbleSearch, then relaunch.

                (\(error))
                """
        }
        let watcher = ChatDBWatcher { [weak self] in
            Task { @MainActor [weak self] in await self?.syncAndRefresh() }
        }
        watcher.start()
        self.watcher = watcher

        // Contacts can fail to load when contactsd holds the AddressBook DB —
        // retry with backoff, then repair names everywhere once they arrive.
        Task { await self.retryContactsIfNeeded() }

        // Coming back from Messages (after it downloaded iCloud attachments):
        // retry any thumbnails that previously failed.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.media.retryFailedThumbnails() }
        }
    }

    /// Manual reload (⌘R / Refresh button): sync from chat.db and reload
    /// everything visible, even if nothing new was indexed.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        media.retryFailedThumbnails()
        Task {
            // ⌘R re-reads contacts (names AND photos) and drops the avatar
            // cache so profile pictures refresh along with everything else.
            _ = try? await engine.reloadContacts()
            media.reloadAvatars()
            _ = try? await engine.syncIndex()
            totalIndexed = (try? await engine.totalIndexed()) ?? totalIndexed
            conversations = (try? await engine.conversations()) ?? conversations
            senderSuggestions = (try? await engine.senderNames()) ?? senderSuggestions
            if selectedKey != nil, convoQuery.isEmpty, anchorRowid == nil {
                await loadThread()
            }
            if !globalQuery.isEmpty { scheduleGlobalSearch() }
            isRefreshing = false
        }
    }

    private func retryContactsIfNeeded() async {
        guard await !engine.contactsAvailable else { return }
        for delaySeconds in [2.0, 5.0, 12.0, 30.0, 60.0] {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let healed = try? await engine.reloadContacts(), healed else { continue }
            // Names arrived: refresh everything that shows them.
            conversations = (try? await engine.conversations()) ?? conversations
            senderSuggestions = (try? await engine.senderNames()) ?? senderSuggestions
            if selectedKey != nil, convoQuery.isEmpty, anchorRowid == nil {
                await loadThread()
            }
            return
        }
    }

    private func syncAndRefresh() async {
        guard let stats = try? await engine.syncIndex(), stats.indexed > 0 else { return }
        totalIndexed = stats.total
        conversations = (try? await engine.conversations()) ?? conversations
        // Live-update an open thread only when the user is viewing the newest messages.
        if selectedKey != nil, convoQuery.isEmpty, anchorRowid == nil {
            await loadThread()
        }
        if !globalQuery.isEmpty { scheduleGlobalSearch() }
    }

    // MARK: - Selection / thread

    private var lastHandledKey: String?
    private var selectionLoadTask: Task<Void, Never>?

    /// Called from the sidebar's selection onChange — must not mutate
    /// `selectedKey` itself (reentrant NSTableView update otherwise).
    ///
    /// The thread load is DEBOUNCED: arrow-keying through the list only kicks
    /// off the expensive chat.db read + decode + enrich once the selection
    /// settles, so fast keyboard scrolling stays smooth.
    func selectionChanged() {
        guard selectedKey != lastHandledKey else { return }
        lastHandledKey = selectedKey
        selectionLoadTask?.cancel()
        selectionLoadTask = Task { @MainActor in
            convoQuery = ""
            convoResults = []
            anchorRowid = nil
            canLoadOlder = true
            try? await Task.sleep(nanoseconds: 120_000_000) // settle before loading
            guard !Task.isCancelled else { return }
            await loadThread()
        }
    }

    func loadThread() async {
        guard let convo = selectedConversation else { return }
        anchorRowid = nil
        showMedia = false
        setThread((try? await engine.recentMessages(chatIds: convo.chatIds, limit: 100)) ?? [])
        canLoadOlder = thread.count >= 100
        requestScroll(.bottom)
    }

    /// Infinite scroll: prepend an older page when the view nears the top.
    func loadOlderIfNeeded() async {
        guard canLoadOlder, !isLoadingOlder,
              let convo = selectedConversation, let first = thread.first else { return }
        isLoadingOlder = true
        let older = (try? await engine.recentMessages(chatIds: convo.chatIds, before: first.date, limit: 120)) ?? []
        if older.isEmpty {
            canLoadOlder = false
        } else {
            setThread(older + thread)
        }
        isLoadingOlder = false
    }

    /// Jump to a reply's original message — scroll if it's loaded, otherwise
    /// reload the thread around it.
    func jumpToReply(_ reply: ReplyPreview) {
        guard let rowid = reply.rowid else { return }
        anchorRowid = rowid
        if thread.contains(where: { $0.rowid == rowid }) {
            requestScroll(.message(rowid))
            return
        }
        guard let convo = selectedConversation, let date = reply.date else { return }
        Task {
            setThread((try? await engine.contextMessages(chatIds: convo.chatIds, around: date, radius: 40)) ?? thread)
            canLoadOlder = true
            requestScroll(.message(rowid))
        }
    }

    /// Jump the thread to the context around a specific message.
    func jump(to hit: Message) async {
        guard let convo = selectedConversation else { return }
        setThread((try? await engine.contextMessages(chatIds: convo.chatIds, around: hit.date, radius: 40)) ?? [])
        anchorRowid = hit.rowid
        canLoadOlder = true
        convoQuery = ""
        convoResults = []
        showMedia = false
        requestScroll(.message(hit.rowid))
    }

    /// Jump the thread to a specific date (nearest message around noon).
    func jumpToDate(_ date: Date) {
        guard let convo = selectedConversation else { return }
        convoQuery = ""
        convoResults = []
        showMedia = false
        Task {
            let target = Calendar.current.startOfDay(for: date).addingTimeInterval(12 * 3600)
            let messages = (try? await engine.contextMessages(chatIds: convo.chatIds, around: target, radius: 60)) ?? []
            guard !messages.isEmpty else { return }
            setThread(messages)
            canLoadOlder = true
            let closest = messages.min {
                abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
            }!
            anchorRowid = closest.rowid
            requestScroll(.message(closest.rowid))
        }
    }

    // MARK: - Media gallery

    func loadMedia() async {
        guard let convo = selectedConversation else { return }
        mediaItems = (try? await engine.mediaItems(chatIds: convo.chatIds)) ?? []
    }

    /// Open the conversation in Messages.app — viewing it there is the only
    /// way to make Messages pull iCloud-evicted attachments back to disk.
    func openInMessages(for message: Message) {
        let convo = message.chatId.flatMap { id in conversations.first { $0.chatIds.contains(id) } }
            ?? selectedConversation
        if let convo, !convo.isGroup, let handle = convo.handle,
           let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "imessage://\(encoded)") {
            NSWorkspace.shared.open(url)
        } else {
            // Group chats have no address-based deep link — just bring up Messages.
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Messages.app"))
        }
    }

    /// Show an advanced-search hit's surrounding conversation in the context pane.
    func selectAdvancedHit(_ hit: Message) {
        advSelectedHit = hit
        guard let chatId = hit.chatId else {
            advContext = []
            return
        }
        Task {
            advContext = (try? await engine.contextMessages(chatIds: [chatId], around: hit.date, radius: 25)) ?? []
        }
    }

    /// Open a search hit in its conversation on the Chats tab.
    func open(hit: Message) {
        guard let chatId = hit.chatId,
              let convo = conversations.first(where: { $0.chatIds.contains(chatId) }) else { return }
        tab = .chats
        lastHandledKey = convo.key // suppress the selection-change reload
        selectedKey = convo.key
        convoQuery = ""
        convoResults = []
        showMedia = false
        Task {
            setThread((try? await engine.contextMessages(chatIds: convo.chatIds, around: hit.date, radius: 40)) ?? [])
            anchorRowid = hit.rowid
            canLoadOlder = true
            requestScroll(.message(hit.rowid))
        }
    }

    // MARK: - Search

    func scheduleGlobalSearch() {
        globalSearchTask?.cancel()
        let query = globalQuery
        let filters = filters
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            globalResults = []
            globalTotal = 0
            return
        }
        globalSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            guard let result = try? await self.engine.search(query: query, filters: filters, limit: 100) else { return }
            guard !Task.isCancelled else { return }
            self.globalResults = result.hits
            self.globalTotal = result.total
            self.globalMillis = result.millis
        }
    }

    func scheduleConvoSearch() {
        convoSearchTask?.cancel()
        let query = convoQuery
        guard let convo = selectedConversation,
              !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            convoResults = []
            convoTotal = 0
            return
        }
        var filters = SearchFilters()
        filters.chatIds = convo.chatIds
        convoSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            guard let result = try? await self.engine.search(query: query, filters: filters, limit: 200) else { return }
            guard !Task.isCancelled else { return }
            self.convoResults = result.hits
            self.convoTotal = result.total
        }
    }

}
