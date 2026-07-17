import Foundation

struct MsgAttachment: Hashable, Sendable {
    let path: String
    let mime: String?
    let isImage: Bool
    let isVideo: Bool
}

struct ReactionBadge: Hashable, Sendable {
    let kind: Int // associated_message_type: 2000 love … 2005 question, 2006+ custom emoji
    let custom: String? // emoji text for custom reactions
    let reactors: [String] // display names, "Me" included
    let fromMe: Bool // I am among the reactors → blue bubble

    var count: Int { reactors.count }
}

struct ReplyPreview: Hashable, Sendable {
    let senderName: String
    let text: String
    var rowid: Int64? // the original message, for jump-to-source
    var date: Date?
}

struct LinkPreview: Hashable, Sendable {
    let url: String
    let title: String?
    let site: String?
}

struct Message: Identifiable, Hashable, Sendable {
    let rowid: Int64
    let guid: String
    let chatId: Int64?
    let chatName: String?
    let isGroup: Bool
    let sender: String?
    let senderName: String
    let isFromMe: Bool
    let date: Date
    let service: String?
    let hasAttachment: Bool
    let text: String
    var attachments: [MsgAttachment] = []
    var reactions: [ReactionBadge] = []
    var replyTo: ReplyPreview?
    var linkPreview: LinkPreview?

    var id: Int64 { rowid }
}

struct MediaItem: Identifiable, Hashable, Sendable {
    let path: String
    let date: Date
    let messageRowid: Int64
    let isVideo: Bool

    var id: String { path }
}

struct Participant: Hashable, Sendable {
    let handle: String
    let name: String
}

struct Conversation: Identifiable, Hashable, Sendable {
    let key: String
    var name: String
    var chatIds: [Int64]
    let isGroup: Bool
    var handle: String? // representative handle for avatar lookup (DMs)
    var lastDate: Date
    var count: Int
    var previewText: String?
    var previewFromMe: Bool
    var previewSender: String?
    var hasAvatar: Bool
    var groupPhotoPath: String? // custom group photo (groups only)
    var participants: [Participant] = [] // first few members, for collage avatars

    var id: String { key }
}

struct SearchFilters: Sendable, Equatable {
    var from: String = ""
    var chat: String = ""
    var after: Date?
    var before: Date?
    var sortByRelevance = false
    var chatIds: [Int64] = []
}

struct SearchResult: Sendable {
    let hits: [Message]
    let total: Int
    let millis: Int
}

struct IndexStats: Sendable {
    let scanned: Int
    let indexed: Int
    let total: Int
}
