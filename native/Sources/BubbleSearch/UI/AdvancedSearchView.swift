import SwiftUI

/// The Advanced Search tab: global as-you-type search, a results list, a
/// conversation-context pane, and a docked filter sidebar on the right.
struct AdvancedSearchView: View {
    @EnvironmentObject var store: AppStore

    private var searching: Bool {
        !store.globalQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchBar
                Divider()
                if !searching {
                    emptyState
                } else {
                    HSplitView {
                        resultsList
                            .frame(minWidth: 320, idealWidth: 400)
                        contextPane
                            .frame(minWidth: 320)
                    }
                }
            }
            if store.showFilterSidebar {
                Divider()
                FilterSidebar()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: store.filters) { store.scheduleGlobalSearch() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search all messages", text: $store.globalQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .onChange(of: store.globalQuery) { store.scheduleGlobalSearch() }
                if searching {
                    Button {
                        store.globalQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9).fill(.quinary))

            if searching {
                Text("\(store.globalTotal.formatted()) matches · \(store.globalMillis) ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    store.showFilterSidebar.toggle()
                }
            } label: {
                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(hasActiveFilters || store.showFilterSidebar ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Search filters")

            RefreshButton()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var hasActiveFilters: Bool {
        !store.filters.from.isEmpty || !store.filters.chat.isEmpty
            || store.filters.after != nil || store.filters.before != nil || store.filters.sortByRelevance
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("Search everything")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Full-text search across all \(store.totalIndexed.formatted()) messages, with from, chat, and date filters.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        List(store.globalResults, selection: Binding(
            get: { store.advSelectedHit?.rowid },
            set: { rowid in
                if let hit = store.globalResults.first(where: { $0.rowid == rowid }) {
                    store.selectAdvancedHit(hit)
                }
            }
        )) { hit in
            SearchHitRow(hit: hit, query: store.globalQuery)
                .tag(hit.rowid)
                .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var contextPane: some View {
        if let hit = store.advSelectedHit {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(hit.chatName ?? hit.senderName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(Fmt.full.string(from: hit.date))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open in Chats") { store.open(hit: hit) }
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.bar)
                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(contextItems) { item in
                                contextItemView(item)
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: store.advContext) {
                        DispatchQueue.main.async {
                            proxy.scrollTo("msg-\(hit.rowid)", anchor: .center)
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "bubble.middle.bottom")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("Select a result to see the conversation")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private enum ContextItem: Identifiable {
        case daySeparator(Date)
        case message(Message, showLabel: Bool)

        var id: String {
            switch self {
            case .daySeparator(let d): return "day-\(Int(d.timeIntervalSince1970))"
            case .message(let m, _): return "msg-\(m.rowid)"
            }
        }
    }

    private var contextItems: [ContextItem] {
        var items: [ContextItem] = []
        var lastDay: Int?
        var lastSender: String?
        var lastDate: Date?
        let cal = Calendar.current
        for m in store.advContext {
            let day = cal.ordinality(of: .day, in: .era, for: m.date) ?? 0
            if day != lastDay {
                items.append(.daySeparator(m.date))
                lastDay = day
                lastSender = nil
            }
            let senderKey = m.isFromMe ? "me" : (m.sender ?? m.senderName)
            let gap = lastDate.map { m.date.timeIntervalSince($0) > 3600 } ?? true
            items.append(.message(m, showLabel: senderKey != lastSender || gap))
            lastSender = senderKey
            lastDate = m.date
        }
        return items
    }

    @ViewBuilder
    private func contextItemView(_ item: ContextItem) -> some View {
        switch item {
        case .daySeparator(let date):
            Text(Fmt.daySep.string(from: date))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity)
        case .message(let message, let showLabel):
            MessageBubble(
                message: message,
                showLabel: showLabel,
                isAnchor: message.rowid == store.advSelectedHit?.rowid
            )
        }
    }
}

/// Docked right sidebar with live-applying search filters.
struct FilterSidebar: View {
    @EnvironmentObject var store: AppStore
    @State private var useAfter = false
    @State private var useBefore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filters")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        store.showFilterSidebar = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            SuggestingField(
                title: "From",
                prompt: "Name or number",
                text: $store.filters.from,
                suggestions: { store.suggest($0, from: store.senderSuggestions) }
            )

            SuggestingField(
                title: "In chat",
                prompt: "Chat or contact name",
                text: $store.filters.chat,
                suggestions: { store.suggest($0, from: store.chatSuggestions) }
            )

            VStack(alignment: .leading, spacing: 6) {
                Toggle("After", isOn: $useAfter)
                    .onChange(of: useAfter) {
                        store.filters.after = useAfter
                            ? (store.filters.after ?? Calendar.current.date(byAdding: .month, value: -1, to: Date()))
                            : nil
                    }
                if useAfter {
                    DatePicker("", selection: Binding(
                        get: { store.filters.after ?? Date() },
                        set: { store.filters.after = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                }

                Toggle("Before", isOn: $useBefore)
                    .onChange(of: useBefore) {
                        store.filters.before = useBefore ? (store.filters.before ?? Date()) : nil
                    }
                if useBefore {
                    DatePicker("", selection: Binding(
                        get: { store.filters.before ?? Date() },
                        set: { store.filters.before = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                }
            }

            Toggle("Sort by relevance", isOn: $store.filters.sortByRelevance)

            Button("Clear Filters") {
                store.filters = SearchFilters()
                useAfter = false
                useBefore = false
            }
            .controlSize(.small)

            Spacer()
        }
        .padding(14)
        .frame(width: 240)
        .background(.bar)
        .onAppear {
            useAfter = store.filters.after != nil
            useBefore = store.filters.before != nil
        }
    }
}

/// Text field with an inline autocomplete dropdown.
struct SuggestingField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let suggestions: (String) -> [String]

    @FocusState private var focused: Bool
    @State private var suppressed = false // true right after picking a suggestion
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onChange(of: text) { suppressed = false }

            let matches = (focused && !suppressed) ? suggestions(text) : []
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(matches, id: \.self) { match in
                        Button {
                            text = match
                            suppressed = true
                        } label: {
                            Text(match)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(hovered == match ? Color.accentColor.opacity(0.18) : .clear)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovered = $0 ? match : (hovered == match ? nil : hovered) }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator, lineWidth: 1)
                )
            }
        }
    }
}
