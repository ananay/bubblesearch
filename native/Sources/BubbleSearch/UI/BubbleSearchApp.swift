import SwiftUI

struct BubbleSearchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = AppStore()
    @StateObject private var updates = SparkleUpdateController()

    var body: some Scene {
        WindowGroup("BubbleSearch") {
            ContentView()
                .environmentObject(store)
                .environmentObject(store.media)
                .environmentObject(updates)
                // minHeight must stay ≤ ~560: a 13.6" MacBook Air with the
                // Dock visible has only ~720-735 pt of usable height, so a
                // taller floor pins the window bottom under the Dock.
                .frame(minWidth: 920, minHeight: 560)
        }
        .defaultSize(width: 1_000, height: 760)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.isAvailable)
            }
            CommandGroup(after: .newItem) {
                Button("Refresh") { store.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Find in Conversation") { store.focusConvoSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Quick Search…") { store.showPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("Chats") { store.tab = .chats }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Advanced Search") { store.tab = .advanced }
                    .keyboardShortcut("2", modifiers: .command)
            }
        }

        Settings {
            SettingsView(updates: updates)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var updates: SparkleUpdateController
    @AppStorage(Telemetry.enabledKey) private var telemetryEnabled = true
    @AppStorage(CrashReporter.enabledKey) private var crashReportsEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Share usage ping", isOn: $telemetryEnabled)
                Text(
                    "Once a day, BubbleSearch sends a persistent install ID, the app version, and your macOS version. Because the ID persists, your IP address and approximate location (from that request) are also recorded. Never your messages, contacts, or search queries. Turning this off sends one final ping recording the opt-out — after that, nothing."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Send crash reports", isOn: $crashReportsEnabled)
                Text(
                    "If BubbleSearch crashed, an anonymous summary (exception type, macOS build, and top stack frames — never message content) is sent on the next launch, under the same install ID as the usage ping. Turning this off sends one final ping recording the opt-out — after that, nothing."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                Button("Check for Updates…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.isAvailable)
                if !updates.isAvailable {
                    Text("Updates are available when running the packaged BubbleSearch.app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
        .onChange(of: telemetryEnabled) { _, enabled in
            if !enabled { Telemetry.sendOptOut(of: "ping") }
        }
        .onChange(of: crashReportsEnabled) { _, enabled in
            if !enabled { Telemetry.sendOptOut(of: "crash") }
        }
    }
}

/// Top-right reload control: syncs from chat.db and reloads the UI (⌘R).
struct RefreshButton: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Button {
            store.refresh()
        } label: {
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(store.isRefreshing)
        .help("Reload from chat.db (⌘R)")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var updates: SparkleUpdateController

    var body: some View {
        ZStack {
            if store.needsFullDiskAccess {
                OnboardingView()
            } else {
                HStack(spacing: 0) {
                    TabRail()
                    Divider()
                    switch store.tab {
                    case .chats:
                        chatsView
                    case .advanced:
                        AdvancedSearchView()
                    }
                }
                if store.isInitialIndexing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Building your search index…")
                            .font(.system(size: 14, weight: .semibold))
                        Text("One-time setup — usually under a minute, even for years of messages.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(radius: 20)
                }
                if store.showPalette {
                    QuickSearchPalette()
                        .transition(.opacity)
                }
            }
        }
        .alert("BubbleSearch", isPresented: .constant(store.startupError != nil)) {
            Button("OK") { store.startupError = nil }
        } message: {
            Text(store.startupError ?? "")
        }
        .background {
            SparkleUpdateTitlebarAccessory(controller: updates)
                .frame(width: 0, height: 0)
        }
    }

    private var chatsView: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 320)
            Divider()
            if let convo = store.selectedConversation {
                ThreadView(conversation: convo)
                    .id(convo.key)
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "message")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("Select a conversation")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Pick a chat to browse and search within it, or use Advanced Search on the left rail.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .topTrailing) {
            RefreshButton()
                .padding(12)
        }
    }
}

/// Vertical tab rail on the far left: Chats and Advanced Search.
struct TabRail: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let logo = AppLogo.image {
                    Image(nsImage: logo)
                        .interpolation(.high)
                        .antialiased(true)
                        .resizable()
                        .frame(width: 30, height: 30)
                } else {
                    Text("B")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 4)

            railButton(.chats, systemImage: "message.fill", help: "Chats")
            railButton(.advanced, systemImage: "magnifyingglass", help: "Advanced Search")

            Spacer()
        }
        .frame(width: 56)
        .background(VisualEffectBackground(material: .sidebar))
    }

    private func railButton(_ tab: AppStore.Tab, systemImage: String, help: String) -> some View {
        Button {
            store.tab = tab
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 38, height: 38)
                .foregroundStyle(store.tab == tab ? .white : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(store.tab == tab ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
