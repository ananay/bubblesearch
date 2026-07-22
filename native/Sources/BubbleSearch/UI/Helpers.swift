import SwiftUI

enum Fmt {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
        return f
    }()

    static let daySep: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f
    }()

    static let full: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// iMessage sidebar style: time today, "Yesterday", weekday, then date.
    static func sidebar(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return time.string(from: date) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day,
           days < 7 { return weekday.string(from: date) }
        return shortDate.string(from: date)
    }
}

/// Highlight query tokens in text (for search results and anchored bubbles).
func highlighted(_ text: String, query: String, baseColor: Color? = nil) -> AttributedString {
    var attr = AttributedString(text)
    if let baseColor { attr.foregroundColor = baseColor }
    for token in query.split(whereSeparator: \.isWhitespace) {
        var searchRange = attr.startIndex..<attr.endIndex
        while let range = attr[searchRange].range(of: String(token), options: [.caseInsensitive, .diacriticInsensitive]) {
            attr[range].backgroundColor = .yellow.opacity(0.45)
            if baseColor != nil { attr[range].foregroundColor = .black }
            guard range.upperBound < searchRange.upperBound else { break }
            searchRange = range.upperBound..<attr.endIndex
        }
    }
    return attr
}

extension Color {
    /// Opaque received-bubble gray (iMessage values). Opaque matters: tapback
    /// badges render BEHIND bubbles, so translucent fills would ghost them.
    static let receivedBubble = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.227, green: 0.227, blue: 0.235, alpha: 1)
            : NSColor(srgbRed: 0.914, green: 0.914, blue: 0.922, alpha: 1)
    })

    /// Received tapback bubble: noticeably LIGHTER than the message bubble in
    /// dark mode (like Messages), slightly darker than it in light mode — so
    /// it stands out against both the bubble and the window background.
    static let tapbackBubble = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.30, green: 0.30, blue: 0.31, alpha: 1)
            : NSColor(srgbRed: 0.87, green: 0.87, blue: 0.885, alpha: 1)
    })
}

/// Behind-window vibrancy — the Messages-sidebar effect where the desktop
/// wallpaper's colors bleed through as a translucent tint. SwiftUI has no
/// direct API for behind-WINDOW blending, hence the representable.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// The SPM resource bundle, resolved by hand. `Bundle.module` must not be
/// referenced anywhere in this target: for executable targets SPM generates
/// it with only two candidates — the .app root (never valid for a signed
/// app, resources live in Contents/Resources) and an absolute .build path
/// on the machine that compiled the release — and it fatalErrors on every
/// other Mac.
private let resourceBundle: Bundle? = {
    let name = "bubblesearch_bubblesearch.bundle"
    let candidates = [
        Bundle.main.resourceURL, // packaged .app: Contents/Resources
        Bundle.main.bundleURL,   // `swift run` / `swift test`: next to the executable
    ]
    for candidate in candidates {
        if let bundle = candidate.flatMap({ Bundle(url: $0.appendingPathComponent(name)) }) {
            return bundle
        }
    }
    return nil
}()

/// The BubbleSearch logo, bundled as an SPM resource.
enum AppLogo {
    static let image: NSImage? = resourceBundle?
        .url(forResource: "logo", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }
}

func initials(of name: String) -> String {
    let parts = name.split(whereSeparator: \.isWhitespace)
        .filter { $0.first?.isLetter == true }
    guard let first = parts.first?.first else { return "#" }
    if parts.count > 1, let second = parts[1].first {
        return String(first).uppercased() + String(second).uppercased()
    }
    return String(first).uppercased()
}
