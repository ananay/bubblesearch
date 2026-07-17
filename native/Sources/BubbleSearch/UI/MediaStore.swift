import SwiftUI

/// Image caches (avatars + attachment thumbnails), isolated from AppStore so
/// that images loading in never invalidate the (expensive) thread structure —
/// only views that actually draw images observe this store.
@MainActor
final class MediaStore: ObservableObject {
    private let engine: Engine
    @Published private var version = 0 // bumped when any image lands

    init(engine: Engine) {
        self.engine = engine
    }

    // MARK: - Avatars

    private var avatarCache: [String: NSImage] = [:]
    private var avatarRequests: Set<String> = []

    func avatar(for conversation: Conversation) -> NSImage? {
        if let cached = avatarCache[conversation.key] { return cached }
        guard !avatarRequests.contains(conversation.key) else { return nil }

        if conversation.isGroup {
            guard let path = conversation.groupPhotoPath else { return nil }
            avatarRequests.insert(conversation.key)
            Task.detached { [weak self] in
                guard let image = NSImage(contentsOfFile: path) else { return }
                await self?.store(image, key: conversation.key)
            }
            return nil
        }

        guard conversation.hasAvatar, let handle = conversation.handle else { return nil }
        avatarRequests.insert(conversation.key)
        Task { [weak self] in
            guard let self else { return }
            guard let data = await self.engine.avatarData(handle: handle, name: conversation.name),
                  let image = NSImage(data: data) else { return }
            self.store(image, key: conversation.key)
        }
        return nil
    }

    /// Per-participant avatar, used for group collage circles.
    func avatar(forHandle handle: String, name: String) -> NSImage? {
        let key = "h:\(handle)"
        if let cached = avatarCache[key] { return cached }
        guard !avatarRequests.contains(key) else { return nil }
        avatarRequests.insert(key)
        Task { [weak self] in
            guard let self else { return }
            guard let data = await self.engine.avatarData(handle: handle, name: name),
                  let image = NSImage(data: data) else { return }
            self.store(image, key: key)
        }
        return nil
    }

    private func store(_ image: NSImage, key: String) {
        avatarCache[key] = image
        version += 1
    }

    // MARK: - Attachment thumbnails

    private var thumbCache: [String: NSImage] = [:]
    private var thumbRequests: Set<String> = []
    private var thumbFailures: Set<String> = []

    func thumbnail(path: String, isVideo: Bool) -> NSImage? {
        if let cached = thumbCache[path] { return cached }
        guard !thumbRequests.contains(path) else { return nil }
        thumbRequests.insert(path)
        Task.detached(priority: .userInitiated) { [weak self] in
            let image = Thumbnailer.make(path: path, isVideo: isVideo)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let image {
                    self.thumbCache[path] = image
                } else {
                    self.thumbFailures.insert(path) // evicted to iCloud
                }
                self.version += 1
            }
        }
        return nil
    }

    func thumbnailFailed(path: String) -> Bool {
        thumbFailures.contains(path)
    }

    /// Drop all cached avatars so they re-fetch (⌘R) — picks up new contact
    /// photos, unmerged cards, and shared name-and-photo updates.
    func reloadAvatars() {
        avatarCache.removeAll()
        avatarRequests.removeAll()
        version += 1
    }

    /// Retry evicted attachments — Messages may have downloaded them since.
    func retryFailedThumbnails() {
        guard !thumbFailures.isEmpty else { return }
        for path in thumbFailures { thumbRequests.remove(path) }
        thumbFailures.removeAll()
        version += 1
    }
}
