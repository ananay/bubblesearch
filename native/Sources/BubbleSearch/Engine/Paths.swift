import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static var chatDB: String {
        ProcessInfo.processInfo.environment["BUBBLESEARCH_CHAT_DB"] ?? "\(home)/Library/Messages/chat.db"
    }

    /// Data directory, migrating indexes built under the project's old names
    /// (isearch → straw → bubblesearch).
    static let dataDir: String = {
        if let env = ProcessInfo.processInfo.environment["BUBBLESEARCH_DATA_DIR"] { return env }
        let current = "\(home)/Library/Application Support/bubblesearch"
        let fm = FileManager.default
        if !fm.fileExists(atPath: current) {
            for legacy in ["\(home)/Library/Application Support/straw",
                           "\(home)/Library/Application Support/isearch"] {
                if fm.fileExists(atPath: legacy) {
                    try? fm.moveItem(atPath: legacy, toPath: current)
                    break
                }
            }
        }
        return current
    }()

    static var indexDB: String {
        try? FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        return "\(dataDir)/index.db"
    }

    static let addressBookDir = "\(home)/Library/Application Support/AddressBook"
    static let nickNameCacheDir = "\(home)/Library/Messages/NickNameCache"
}
