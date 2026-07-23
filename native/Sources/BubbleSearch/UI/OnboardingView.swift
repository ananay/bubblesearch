import SwiftUI

/// First-run setup: shown whenever the Messages database isn't readable,
/// which almost always means Full Disk Access hasn't been granted yet.
/// AppStore polls in the background and dismisses this automatically the
/// moment access appears.
struct OnboardingView: View {
    private var isAppBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 14) {
                    if let logo = AppLogo.image {
                        // No .shadow() here: the Icon Composer artwork has its own
                        // baked shadow — doubling it dirties the edges.
                        Image(nsImage: logo)
                            .interpolation(.high)
                            .antialiased(true)
                            .resizable()
                            .frame(width: 96, height: 96)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 56, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                    Text("Welcome to BubbleSearch")
                        .font(.system(size: 28, weight: .bold))
                    Text(
                        "Blazing-fast, fully local search for your entire iMessage history.\nEverything stays on this Mac."
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.accentColor)
                        Text("One-time setup: Full Disk Access")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(
                        "BubbleSearch reads the Messages database directly (read-only) to search your texts. macOS protects that file behind Full Disk Access, so it needs your permission once."
                    )
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    if isAppBundle {
                        draggableAppTile
                            .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        setupStep(1, "Click **Open System Settings** below")
                        setupStep(
                            2,
                            isAppBundle
                                ? "**Drag the icon above** into the Full Disk Access list, then switch it on"
                                : "Click **+**, choose **BubbleSearch** in Applications, and switch it on")
                        setupStep(3, "If macOS asks, choose **Quit & Reopen** — or use the button below")
                    }

                    HStack(spacing: 10) {
                        Button {
                            NSWorkspace.shared.open(
                                URL(
                                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                                )!
                            )
                        } label: {
                            Text("Open System Settings")
                                .frame(minWidth: 160)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            relaunch()
                        } label: {
                            Text("Relaunch BubbleSearch")
                                .frame(minWidth: 160)
                        }
                        .controlSize(.large)
                        .disabled(!isAppBundle)
                    }
                    .frame(maxWidth: .infinity)

                    Text("This screen disappears automatically once access is granted.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
                .padding(22)
                .frame(maxWidth: 460)
                .background(RoundedRectangle(cornerRadius: 16).fill(.quinary))

                Text("Private by design. All searching is done locally on your computer and not sent out.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, 20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var appURL: URL {
        URL(fileURLWithPath: Bundle.main.bundlePath)
    }

    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    /// Perplexity-style: the app itself as a draggable tile — drop it straight
    /// onto the Full Disk Access list in System Settings.
    private var draggableAppTile: some View {
        VStack(spacing: 6) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Drag me into the Full Disk Access list")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(Color.accentColor.opacity(0.55))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onDrag {
            NSItemProvider(contentsOf: appURL) ?? NSItemProvider()
        } preview: {
            HStack(spacing: 8) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 32, height: 32)
                Text("Drag to Full Disk Access")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
        }
        .help("Drag this onto the Full Disk Access list in System Settings")
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(.init(text))
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true) // wrap, never truncate
        }
    }

    private func relaunch() {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { return }
        let process = Process()
        process.launchPath = "/bin/sh"
        process.arguments = ["-c", "sleep 0.4; /usr/bin/open \"\(path)\""]
        try? process.run()
        NSApp.terminate(nil)
    }
}
