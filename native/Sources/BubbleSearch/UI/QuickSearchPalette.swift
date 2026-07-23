import SwiftUI

/// ⌘K palette: type to search all messages, ↑/↓ to pick, Enter to jump to the
/// message in its conversation, Esc to dismiss.
struct QuickSearchPalette: View {
    @EnvironmentObject var store: AppStore
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { store.showPalette = false }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                    TextField("Search messages…", text: $store.paletteQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17))
                        .focused($focused)
                        .task(id: store.paletteQuery) { await store.runPaletteSearch() }
                        .onSubmit { store.openPaletteSelection() }
                        .onKeyPress(.downArrow) {
                            store.movePaletteSelection(1)
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            store.movePaletteSelection(-1)
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            store.showPalette = false
                            return .handled
                        }
                    Text("esc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.quinary))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                if !store.paletteConvos.isEmpty || !store.paletteResults.isEmpty {
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                // NOTE: row identities are globally unique and
                                // stable ("p-<key>" / "m-<rowid>") — positional
                                // ids collide across the two sections as counts
                                // shift, making SwiftUI render ghost rows.
                                if !store.paletteConvos.isEmpty {
                                    sectionHeader("People & Chats")
                                    ForEach(Array(store.paletteConvos.enumerated()), id: \.element.key) { index, convo in
                                        personRow(convo, selected: index == store.paletteIndex)
                                            .id("p-\(convo.key)")
                                            .onTapGesture {
                                                store.paletteIndex = index
                                                store.openPaletteSelection()
                                            }
                                    }
                                }
                                if !store.paletteResults.isEmpty {
                                    sectionHeader("Messages")
                                    ForEach(Array(store.paletteResults.enumerated()), id: \.element.rowid) { index, hit in
                                        let globalIndex = store.paletteConvos.count + index
                                        paletteRow(hit, selected: globalIndex == store.paletteIndex)
                                            .id("m-\(hit.rowid)")
                                            .onTapGesture {
                                                store.paletteIndex = globalIndex
                                                store.openPaletteSelection()
                                            }
                                    }
                                }
                            }
                            .padding(6)
                        }
                        .frame(maxHeight: 380)
                        .onChange(of: store.paletteIndex) {
                            if let id = store.paletteScrollID {
                                proxy.scrollTo(id, anchor: nil)
                            }
                        }
                    }
                } else if !store.paletteQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    Divider()
                    Text("No matches")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 24)
                }
            }
            .frame(width: 640)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
            .padding(.top, 90)
        }
        // Setting FocusState in the same update that inserts the view is
        // routinely dropped on macOS (the field isn't registered with the
        // focus system yet), and focus then falls to the window's first
        // text field — the sidebar's "Filter conversations". defaultFocus
        // claims initial focus for this scope; the async re-set covers OSes
        // where defaultFocus alone doesn't move an already-active focus.
        .defaultFocus($focused, true)
        .onAppear {
            focused = true
            DispatchQueue.main.async { focused = true }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func personRow(_ convo: Conversation, selected: Bool) -> some View {
        HStack(spacing: 10) {
            AvatarView(conversation: convo, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(convo.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(convo.isGroup ? "\(convo.count.formatted()) messages" : (convo.handle ?? ""))
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? .white.opacity(0.8) : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "return")
                .font(.system(size: 10))
                .foregroundStyle(selected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
        )
        .contentShape(Rectangle())
    }

    private func paletteRow(_ hit: Message, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(hit.isFromMe ? "Me" : hit.senderName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if hit.isGroup, let chat = hit.chatName {
                    Text("in \(chat)")
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? .white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(Fmt.sidebar(hit.date))
                    .font(.system(size: 10.5))
                    .foregroundStyle(selected ? .white.opacity(0.8) : Color.secondary)
            }
            Text(highlighted(String(hit.text.prefix(160)), query: store.paletteQuery))
                .font(.system(size: 12))
                .foregroundStyle(selected ? .white.opacity(0.92) : Color.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
        )
        .contentShape(Rectangle())
    }
}
