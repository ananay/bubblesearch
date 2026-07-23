import Foundation

/// Anonymous daily-active ping: a random install UUID (generated once, tied
/// to nothing), app version, and macOS version. Never message content,
/// contacts, or queries. One request per day, and only if the user hasn't
/// turned it off in Settings.
enum Telemetry {
    static let enabledKey = "telemetryEnabled"

    /// Custom domain on the user's personal Cloudflare account — the only
    /// endpoint this app ever POSTs to, at most once per day.
    private static let endpoint: URL? = URL(string: "https://bst.0xaa.io/ping")

    private static let installIDKey = "telemetryInstallID"
    private static let lastPingKey = "telemetryLastPingDate"

    /// Random per-install UUID shared by the daily ping and crash reports.
    /// Generated once, tied to nothing.
    static var installID: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: installIDKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: installIDKey)
        return id
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// One final, disclosed ping recording an opt-out, sent at the moment a
    /// sharing toggle is switched off (the Settings captions say exactly
    /// this). Fire-and-forget; nothing further is sent afterwards.
    static func sendOptOut(of setting: String) {
        guard let url = URL(string: "https://bst.0xaa.io/optout") else { return }
        let payload: [String: String] = [
            "id": installID,
            "version": appVersion,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "setting": setting,
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BubbleSearch/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request).resume()
    }

    static func pingIfNeeded() {
        guard let endpoint else { return }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: enabledKey) as? Bool ?? true else { return }

        let today = ISO8601DateFormatter.dateOnly.string(from: Date())
        guard defaults.string(forKey: lastPingKey) != today else { return }

        let version = appVersion
        let payload: [String: String] = [
            "id": installID,
            "version": version,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Identifies genuine app pings; the worker stores only requests whose
        // UA starts with "BubbleSearch/" (version part ignored).
        request.setValue("BubbleSearch/\(version)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                defaults.set(today, forKey: lastPingKey)
            }
            // Any failure: silently retry on a future launch/day.
        }.resume()
    }
}

private extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
