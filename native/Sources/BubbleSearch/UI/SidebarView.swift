import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: AppStore

    private enum Focus: Hashable {
        case filter, list
    }

    @FocusState private var focus: Focus?

    var body: some View {
        VStack(spacing: 0) {
            filterField
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            conversationList
        }
        .background(VisualEffectBackground(material: .sidebar))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text("\(store.totalIndexed.formatted()) messages indexed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.bar)
        }
    }

    private var filterField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Filter conversations", text: $store.convoFilter)
                .textFieldStyle(.plain)
                .focused($focus, equals: .filter)
                .onKeyPress(.downArrow) {
                    // Arrow-down from the filter drops into the list.
                    let convos = store.filteredConversations
                    guard !convos.isEmpty else { return .handled }
                    if store.selectedKey == nil || !convos.contains(where: { $0.key == store.selectedKey }) {
                        store.selectedKey = convos[0].key
                    }
                    focus = .list
                    return .handled
                }
            if !store.convoFilter.isEmpty {
                Button {
                    store.convoFilter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quinary))
    }

    private var conversationList: some View {
        List(store.filteredConversations, selection: $store.selectedKey) { convo in
            ConversationRow(conversation: convo)
                .tag(convo.key)
                .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                .listRowSeparator(.visible)
                .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 54 }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .focused($focus, equals: .list)
        .onChange(of: store.selectedKey) {
            store.selectionChanged()
        }
    }
}

struct ConversationRow: View {
    @EnvironmentObject var store: AppStore
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(conversation: conversation, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Fmt.sidebar(conversation.lastDate))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Text(previewLine)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 11)
    }

    private var previewLine: String {
        guard var text = conversation.previewText else { return "" }
        if text.count > 60 { text = String(text.prefix(60)) + "…" }
        if conversation.previewFromMe { return text }
        if conversation.isGroup, let sender = conversation.previewSender?.split(separator: " ").first {
            return "\(sender): \(text)"
        }
        return text
    }
}

struct SearchHitRow: View {
    let hit: Message
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(hit.isFromMe ? "Me" : hit.senderName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if hit.isGroup, let chat = hit.chatName {
                    Text(chat)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(Fmt.sidebar(hit.date))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Text(highlighted(String(hit.text.prefix(220)), query: query))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}
