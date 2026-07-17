import SwiftUI

struct AvatarView: View {
    @EnvironmentObject var media: MediaStore
    let conversation: Conversation
    var size: CGFloat = 42

    var body: some View {
        Group {
            if conversation.isGroup {
                if let image = media.avatar(for: conversation) {
                    // Custom group photo.
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    groupAvatar
                }
            } else {
                PersonCircle(handle: conversation.handle, name: conversation.name, size: size)
            }
        }
        .frame(width: size, height: size)
    }

    /// Messages-style collage: two overlapping member circles.
    @ViewBuilder
    private var groupAvatar: some View {
        let members = conversation.participants
        if members.count >= 2 {
            ZStack {
                PersonCircle(handle: members[1].handle, name: members[1].name, size: size * 0.62)
                    .offset(x: size * 0.17, y: -size * 0.17)
                PersonCircle(handle: members[0].handle, name: members[0].name, size: size * 0.66)
                    .overlay(
                        Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                    )
                    .offset(x: -size * 0.13, y: size * 0.15)
            }
        } else if let only = members.first {
            PersonCircle(handle: only.handle, name: only.name, size: size)
        } else {
            MonogramCircle(size: size) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(.white)
            }
        }
    }
}

/// A single person's circle: photo if available, monogram initials otherwise.
struct PersonCircle: View {
    @EnvironmentObject var media: MediaStore
    let handle: String?
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let handle, let image = media.avatar(forHandle: handle, name: name) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                MonogramCircle(size: size) {
                    Text(initials(of: name))
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct MonogramCircle<Content: View>: View {
    let size: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.63, green: 0.65, blue: 0.68), Color(red: 0.46, green: 0.48, blue: 0.52)],
            startPoint: .top, endPoint: .bottom
        )
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { content }
    }
}
