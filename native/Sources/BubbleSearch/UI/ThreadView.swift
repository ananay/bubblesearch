import SwiftUI

struct ThreadView: View {
    @EnvironmentObject var store: AppStore
    let conversation: Conversation
    @FocusState private var searchFocused: Bool
    @State private var showDateJump = false
    @State private var jumpDate = Date()
    @State private var dateRange: ClosedRange<Date>?

    private var searchingConvo: Bool {
        !store.convoQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.showMedia {
                MediaGridView(conversation: conversation)
            } else if searchingConvo {
                convoResults
            } else {
                messageScroll
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            AvatarView(conversation: conversation, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(conversation.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Search this conversation", text: $store.convoQuery)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 240)
                    .focused($searchFocused)
                    .onChange(of: store.convoQuery) { store.scheduleConvoSearch() }
                    .onChange(of: store.convoSearchFocusTick) { searchFocused = true }
                if searchingConvo {
                    Button {
                        store.convoQuery = ""
                        Task { await store.loadThread() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(.quinary))

            Button {
                store.showMedia.toggle()
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(store.showMedia ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Photos & videos in this conversation")

            Button {
                showDateJump.toggle()
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Jump to a date in this conversation")
            .popover(isPresented: $showDateJump, arrowEdge: .bottom) {
                VStack(spacing: 10) {
                    Text("Jump to date")
                        .font(.system(size: 13, weight: .semibold))

                    DatePicker(
                        "",
                        selection: $jumpDate,
                        in: dateRange ?? Date.distantPast...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 240)

                    Button("Jump") {
                        showDateJump = false
                        store.jumpToDate(jumpDate)
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(12)
                .task {
                    dateRange = try? await store.engine.dateRange(chatIds: conversation.chatIds)
                    if let range = dateRange, jumpDate > range.upperBound || jumpDate < range.lowerBound {
                        jumpDate = range.upperBound
                    }
                }
            }

            RefreshButton()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !conversation.isGroup, let handle = conversation.handle { parts.append(handle) }
        parts.append("\(conversation.count.formatted()) messages")
        return parts.joined(separator: " · ")
    }

    // MARK: - Thread (infinite scroll, bottom-anchored)

    private var messageScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    if store.isLoadingOlder {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, 8)
                    }
                    // threadRows are precomputed in the store — this ForEach
                    // does zero per-render work beyond identity diffing.
                    ForEach(store.threadRows) { row in
                        threadRowView(row)
                            .id(row.id)
                            .onAppear {
                                // Prefetch older messages as the top approaches.
                                if row.id == store.topTriggerRowid {
                                    Task { await store.loadOlderIfNeeded() }
                                }
                            }
                    }
                    Color.clear.frame(height: 6).id("bottom")
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onAppear { performScroll(proxy) }
            .onChange(of: store.scrollTick) { performScroll(proxy) }
        }
    }

    private func performScroll(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            switch store.scrollTarget {
            case .bottom:
                proxy.scrollTo("bottom", anchor: .bottom)
            case .message(let rowid):
                proxy.scrollTo(rowid, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func threadRowView(_ row: AppStore.ThreadRow) -> some View {
        switch row.kind {
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
                isAnchor: message.rowid == store.anchorRowid
            )
        }
    }

    // MARK: - In-conversation search results

    private var convoResults: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(store.convoTotal.formatted()) matches in this conversation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            List(store.convoResults) { hit in
                SearchHitRow(hit: hit, query: store.convoQuery)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await store.jump(to: hit) }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - Message bubble (text, media, reply quote, tapbacks)

struct MessageBubble: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var media: MediaStore
    let message: Message
    let showLabel: Bool
    let isAnchor: Bool

    private var mediaAttachments: [MsgAttachment] {
        message.attachments.filter { $0.isImage || $0.isVideo }
    }

    private var fileAttachments: [MsgAttachment] {
        message.attachments.filter { !$0.isImage && !$0.isVideo }
    }

    var body: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
            if showLabel {
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            content
                .padding(.top, message.reactions.isEmpty ? 0 : 22)
        }
        .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
    }

    /// Hang the tapback bubbles off the given view's top corner — applied to
    /// the topmost visible bubble element (media if present, else text).
    @ViewBuilder
    private func withTapbacks<V: View>(_ view: V, isTarget: Bool) -> some View {
        if isTarget && !message.reactions.isEmpty {
            // Fully visible badge at the bubble's top corner: it sits mostly
            // ABOVE the bubble, dipping only ~8pt into the corner rounding —
            // so it never covers text.
            view.overlay(alignment: message.isFromMe ? .topLeading : .topTrailing) {
                let badges = message.reactions
                HStack(spacing: -5) {
                    ForEach(Array(badges.enumerated()), id: \.element) { index, badge in
                        TapbackBubble(
                            badge: badge,
                            onMyMessage: message.isFromMe,
                            // Only the OUTERMOST badge gets the tail dot, and
                            // it stacks in front of the others.
                            showTail: message.isFromMe ? index == 0 : index == badges.count - 1
                        )
                        .zIndex(message.isFromMe ? Double(badges.count - index) : Double(index))
                    }
                }
                .offset(x: message.isFromMe ? -10 : 10, y: -24)
            }
        } else {
            view
        }
    }

    private var tapbackOnMedia: Bool { !mediaAttachments.isEmpty }
    private var tapbackOnChip: Bool { mediaAttachments.isEmpty && !fileAttachments.isEmpty }
    private var tapbackOnCard: Bool { message.attachments.isEmpty && message.linkPreview != nil }
    private var tapbackOnText: Bool { message.attachments.isEmpty && message.linkPreview == nil }

    /// Link messages carry the raw URL as their text — the card replaces it.
    private var showTextBubble: Bool {
        !message.text.isEmpty && !(message.linkPreview != nil && message.text.hasPrefix("http"))
    }

    private var content: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
            if let reply = message.replyTo, !reply.text.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 8))
                    Text("\(reply.senderName): \(reply.text)")
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(.quinary))
                .contentShape(Capsule())
                .onTapGesture { store.jumpToReply(reply) }
                .help("Jump to the original message")
            }

            ForEach(mediaAttachments, id: \.self) { att in
                withTapbacks(mediaView(att), isTarget: tapbackOnMedia && att == mediaAttachments.first)
            }

            ForEach(fileAttachments, id: \.self) { att in
                withTapbacks(fileChip(att), isTarget: tapbackOnChip && att == fileAttachments.first)
            }

            if let link = message.linkPreview {
                withTapbacks(linkCard(link), isTarget: tapbackOnCard)
            }

            if showTextBubble {
                textBubble
            }
        }
    }

    /// Rich-link preview card (URL messages), like iMessage's link bubble.
    private func linkCard(_ link: LinkPreview) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(link.title ?? link.url)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(message.isFromMe ? .white : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 9))
                Text(link.site ?? (URL(string: link.url)?.host ?? link.url))
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .foregroundStyle(message.isFromMe ? .white.opacity(0.75) : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(message.isFromMe ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(Color.receivedBubble))
        )
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .onTapGesture {
            if let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
        }
        .help(link.url)
    }

    private var textBubble: some View {
        withTapbacks(
            Text(message.text)
                .font(.system(size: 13))
                .foregroundStyle(message.isFromMe ? .white : .primary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(message.isFromMe ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(Color.receivedBubble))
                )
                .overlay {
                    if isAnchor {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(.yellow, lineWidth: 2)
                    }
                }
                .contextMenu {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    }
                },
            isTarget: tapbackOnText
        )
        // Width cap applied OUTSIDE the tapback overlay so badges anchor to
        // the visible bubble, not this (wider) layout frame.
        .frame(maxWidth: 480, alignment: message.isFromMe ? .trailing : .leading)
    }

    @ViewBuilder
    private func mediaView(_ att: MsgAttachment) -> some View {
        Group {
            if let thumb = media.thumbnail(path: att.path, isVideo: att.isVideo) {
                // Frame matches the image's own aspect so the rounded corners
                // always hug the picture (no letterboxed straight edges).
                let size = Self.fittedSize(thumb.size)
                Image(nsImage: thumb)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        if att.isVideo {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(radius: 4)
                        }
                    }
            } else if media.thumbnailFailed(path: att.path) {
                // Evicted to iCloud — Messages only re-downloads it when the
                // conversation is viewed there, so offer that jump.
                HStack(spacing: 5) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 11))
                    Text(att.isVideo ? "Video in iCloud" : "Photo in iCloud")
                        .font(.system(size: 12))
                    Text("· open in Messages to download")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.receivedBubble))
                .help("Messages keeps this in iCloud. Click to open the conversation in Messages — viewing it downloads the file; BubbleSearch picks it up when you come back.")
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quinary)
                    .frame(width: 220, height: 150)
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .onTapGesture {
            openAttachment(att)
        }
    }

    private static func fittedSize(_ s: NSSize) -> CGSize {
        guard s.width > 0, s.height > 0 else { return CGSize(width: 220, height: 150) }
        let scale = min(280 / s.width, 320 / s.height, 1)
        return CGSize(width: s.width * scale, height: s.height * scale)
    }

    private func openAttachment(_ att: MsgAttachment) {
        if media.thumbnailFailed(path: att.path) {
            store.openInMessages(for: message) // evicted — trigger download there
        } else {
            openMediaFile(path: att.path, isImage: att.isImage)
        }
    }

    private func fileChip(_ att: MsgAttachment) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "paperclip")
                .font(.system(size: 11))
            Text((att.path as NSString).lastPathComponent)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.receivedBubble))
        .frame(maxWidth: 300, alignment: .leading)
        .onTapGesture {
            NSWorkspace.shared.open(URL(fileURLWithPath: att.path))
        }
    }

    private var label: String {
        let who = message.isFromMe ? "Me" : message.senderName
        return "\(who) · \(Fmt.time.string(from: message.date))"
    }
}

/// iMessage-style tapback: a small circular bubble with a tail dot, hung off
/// the corner of the message bubble. Blue when I reacted, gray otherwise.
/// Click to see who reacted.
struct TapbackBubble: View {
    let badge: ReactionBadge
    let onMyMessage: Bool // reactions to my messages hang off the leading corner
    var showTail = true // only the outermost badge in a row carries the tail
    @State private var showReactors = false
    @State private var appeared = false

    private var bubbleFill: AnyShapeStyle {
        badge.fromMe
            ? AnyShapeStyle(Color.blue.gradient)
            : AnyShapeStyle(Color.tapbackBubble)
    }

    private var glyphColor: Color {
        badge.fromMe ? .white : .secondary
    }

    var body: some View {
        HStack(spacing: 3) {
            glyph
            if badge.count > 1 {
                Text("\(badge.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(glyphColor)
            }
        }
        .padding(.horizontal, badge.count > 1 ? 8 : 0)
        .frame(minWidth: 32, minHeight: 32)
        .background(Capsule().fill(bubbleFill))
        // Tail dot on the OUTER side — opposite the message bubble.
        .overlay(alignment: onMyMessage ? .bottomLeading : .bottomTrailing) {
            if showTail {
                Circle()
                    .fill(bubbleFill)
                    .frame(width: 9, height: 9)
                    .offset(x: onMyMessage ? -4 : 4, y: 4)
            }
        }
        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
        .scaleEffect(appeared ? 1 : 0.05, anchor: onMyMessage ? .bottomLeading : .bottomTrailing)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.58)) { appeared = true }
        }
        .contentShape(Capsule())
        .onTapGesture { showReactors.toggle() }
        .popover(isPresented: $showReactors, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(badge.reactors, id: \.self) { name in
                    HStack(spacing: 6) {
                        glyph
                        Text(name)
                            .font(.system(size: 12.5))
                    }
                }
            }
            .padding(12)
        }
        .help(badge.reactors.joined(separator: ", "))
    }

    @ViewBuilder
    private var glyph: some View {
        if let art = TapbackArt.colored[badge.kind] {
            // The ACTUAL colored artwork Messages renders (ChatKit animation
            // final frames), alpha-cropped so it fills the bubble like iMessage.
            Image(nsImage: art)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)
        } else if let art = TapbackArt.templates[badge.kind] {
            // Monochrome template fallback, tinted like Messages.
            Image(nsImage: art)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: 22)
                .foregroundStyle(tint)
        } else if let sf = TapbackArt.sfFallbacks[badge.kind] {
            Image(systemName: sf)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
        } else {
            Text(badge.custom ?? "❤️")
                .font(.system(size: 20))
        }
    }

    private var tint: Color {
        if badge.kind == 2000 { return Color(red: 1.0, green: 0.22, blue: 0.55) }
        return badge.fromMe ? .white : .secondary
    }
}

/// Images open in Preview specifically; videos go to their default player.
func openMediaFile(path: String, isImage: Bool) {
    let url = URL(fileURLWithPath: path)
    if isImage {
        let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
        NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
    } else {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Media gallery grid

struct MediaGridView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var media: MediaStore
    let conversation: Conversation

    var body: some View {
        ScrollView {
            if store.mediaItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No photos or videos in this conversation")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 4)], spacing: 4) {
                    ForEach(store.mediaItems) { item in
                        mediaCell(item)
                    }
                }
                .padding(10)
            }
        }
        .task(id: conversation.key) {
            await store.loadMedia()
        }
    }

    private func mediaCell(_ item: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let thumb = media.thumbnail(path: item.path, isVideo: item.isVideo) {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 130, maxWidth: .infinity)
                    .frame(height: 130)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.quinary)
                    .frame(height: 130)
                    .overlay { ProgressView().controlSize(.small) }
            }
            if item.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .padding(5)
                    .shadow(radius: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            openMediaFile(path: item.path, isImage: !item.isVideo)
        }
        .help(Fmt.full.string(from: item.date))
    }
}
