import Foundation

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            do {
                try SelfTest.run()
                exit(0)
            } catch {
                print("SELFTEST FAILED: \(error)")
                exit(1)
            }
        }
        BubbleSearchApp.main()
    }
}

enum SelfTest {
    static func run() throws {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                let engine = try Engine()

                print("tapback art — colored: \(TapbackArt.colored.count)/6, templates: \(TapbackArt.templates.count)/6")
                let stats = try await engine.syncIndex()
                print("sync: scanned \(stats.scanned), indexed \(stats.indexed), total \(stats.total)")

                let result = try await engine.search(query: "dinner", limit: 3)
                print("search 'dinner': \(result.total) matches in \(result.millis) ms")
                for hit in result.hits {
                    print("  [\(hit.senderName)] \(hit.text.prefix(60))")
                }

                let convos = try await engine.conversations()
                print("conversations: \(convos.count)")
                let dms = convos.prefix(50).filter { !$0.isGroup }
                let withAvatar = dms.filter(\.hasAvatar).count
                print("top-50 DMs with avatar: \(withAvatar)/\(dms.count)")

                // The Hunar case: photo stored as a 0x02 external-data ref.
                if let hunar = convos.first(where: { $0.name == "Hunar Batra" }) {
                    let bytes = await engine.avatarData(handle: hunar.handle ?? "", name: hunar.name)
                    print("Hunar avatar: hasAvatar=\(hunar.hasAvatar), bytes=\(bytes?.count ?? 0)")
                }

                let groups = convos.filter(\.isGroup)
                let withPhoto = groups.filter { $0.groupPhotoPath != nil }
                let withMembers = groups.filter { !$0.participants.isEmpty }
                print("groups: \(groups.count), custom photo: \(withPhoto.count), collage-able: \(withMembers.count)")
                if let g = withPhoto.first {
                    print("sample group photo: \(g.name) → \(g.groupPhotoPath ?? "")")
                }
                if let first = convos.first {
                    print("first: \(first.name) (\(first.count) msgs, chats \(first.chatIds))")
                    let thread = try await engine.recentMessages(chatIds: first.chatIds, limit: 5)
                    print("thread tail: \(thread.count) messages, last: \(thread.last?.text.prefix(40) ?? "")")
                }

                // Rich-content checks on the busiest group chat.
                if let group = convos.first(where: { $0.isGroup && $0.count > 500 }) {
                    let msgs = try await engine.recentMessages(chatIds: group.chatIds, limit: 200)
                    let attachmentCount = msgs.map(\.attachments.count).reduce(0, +)
                    let reactionCount = msgs.map(\.reactions.count).reduce(0, +)
                    let replyCount = msgs.compactMap(\.replyTo).count
                    let attachmentOnly = msgs.filter { $0.text.isEmpty && !$0.attachments.isEmpty }.count
                    print("rich (\(group.name), last 200): \(attachmentCount) attachments (\(attachmentOnly) attachment-only msgs), \(reactionCount) tapback badges, \(replyCount) replies")
                    let media = try await engine.mediaItems(chatIds: group.chatIds, limit: 50)
                    print("media gallery: \(media.count) items, \(media.filter(\.isVideo).count) videos")
                }

                var linkCount = 0
                var sample: LinkPreview?
                for convo in convos.prefix(8) {
                    let msgs = try await engine.recentMessages(chatIds: convo.chatIds, limit: 60)
                    for m in msgs where m.linkPreview != nil {
                        linkCount += 1
                        if sample == nil { sample = m.linkPreview }
                    }
                }
                print("link previews (top-8 convos, last 60 msgs): \(linkCount), sample: \(sample?.title ?? sample?.url ?? "none") [\(sample?.site ?? "?")]")

                if let first = convos.first, let handle = first.handle, first.hasAvatar {
                    let data = await engine.avatarData(handle: handle, name: first.name)
                    print("avatar bytes: \(data?.count ?? 0)")
                }
                semaphore.signal()
            } catch {
                print("SELFTEST FAILED: \(error)")
                exit(1)
            }
        }
        semaphore.wait()
    }
}
