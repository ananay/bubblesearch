import Foundation

/// Anonymous crash reporting, riding the same opt-in as the daily ping.
///
/// On launch, scan this user's ~/Library/Logs/DiagnosticReports for crash
/// logs (.ips) belonging to BubbleSearch that appeared since the last scan,
/// and upload a compact summary: crash time, app version, macOS build,
/// exception type, and the top stack frames of the crashed thread. Never
/// message content, contacts, or queries — the payload is derived only from
/// the crash log's metadata, and nothing is sent when the telemetry toggle
/// is off.
enum CrashReporter {
    static let enabledKey = "crashReportsEnabled"

    private static let endpoint: URL? = URL(string: "https://bst.0xaa.io/crash")

    /// One-time migration: crash reporting originally rode the usage-ping
    /// toggle. Anyone who opted out under that combined switch must stay
    /// opted out of crash reports until they explicitly re-enable them.
    static func migrateSettingIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: enabledKey) == nil else { return }
        if let telemetry = defaults.object(forKey: Telemetry.enabledKey) as? Bool, !telemetry {
            defaults.set(false, forKey: enabledKey)
        }
    }

    /// Filename of the newest crash log successfully uploaded. macOS names
    /// reports "BubbleSearch-YYYY-MM-DD-HHMMSS.ips", so string order is
    /// chronological order.
    private static let lastReportedKey = "crashLastReportedFile"

    /// Cap per launch so a crash loop can't flood the endpoint.
    private static let maxReportsPerLaunch = 3

    static func reportNewCrashesIfEnabled() {
        guard let endpoint else { return }
        migrateSettingIfNeeded()
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: enabledKey) as? Bool ?? true else { return }

        DispatchQueue.global(qos: .utility).async {
            let reportsDir = FileManager.default
                .urls(for: .libraryDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("Logs/DiagnosticReports")
            guard let reportsDir,
                  let names = try? FileManager.default.contentsOfDirectory(atPath: reportsDir.path)
            else { return }

            let lastReported = defaults.string(forKey: lastReportedKey) ?? ""
            let fresh = names
                .filter { $0.hasPrefix("BubbleSearch-") && $0.hasSuffix(".ips") && $0 > lastReported }
                .sorted()
                .prefix(maxReportsPerLaunch)

            for name in fresh {
                guard
                    let text = try? String(contentsOf: reportsDir.appendingPathComponent(name), encoding: .utf8),
                    let summary = parse(ips: text),
                    summary.bundleID == "com.ananayarora.bubblesearch"
                else { continue }
                if send(summary, to: endpoint) {
                    defaults.set(name, forKey: lastReportedKey)
                } else {
                    break // endpoint unreachable — retry this file next launch
                }
            }
        }
    }

    struct Summary {
        var bundleID = ""
        var crashTime = ""
        var version = ""
        var os = ""
        var exception = ""
        var frames = ""
    }

    /// A modern .ips crash log is two JSON documents: a one-line header
    /// (app/OS versions, crash time) followed by the report body.
    static func parse(ips text: String) -> Summary? {
        guard let newline = text.firstIndex(of: "\n"),
              let header = try? JSONSerialization.jsonObject(
                with: Data(text[..<newline].utf8)) as? [String: Any],
              let body = try? JSONSerialization.jsonObject(
                with: Data(text[text.index(after: newline)...].utf8)) as? [String: Any]
        else { return nil }

        var summary = Summary()
        summary.bundleID = header["bundleID"] as? String ?? ""
        summary.crashTime = header["timestamp"] as? String ?? ""
        summary.version = header["app_version"] as? String ?? ""
        summary.os = header["os_version"] as? String ?? ""

        if let exception = body["exception"] as? [String: Any] {
            summary.exception = [exception["type"], exception["signal"]]
                .compactMap { $0 as? String }
                .joined(separator: " / ")
        }
        if let termination = body["termination"] as? [String: Any],
           let indicator = termination["indicator"] as? String {
            summary.exception += summary.exception.isEmpty ? indicator : " — \(indicator)"
        }

        let threads = body["threads"] as? [[String: Any]] ?? []
        let images = body["usedImages"] as? [[String: Any]] ?? []
        let faulting = body["faultingThread"] as? Int ?? 0
        let crashed = threads.indices.contains(faulting)
            ? threads[faulting]
            : threads.first { ($0["triggered"] as? Bool) == true }
        summary.frames = (crashed?["frames"] as? [[String: Any]] ?? [])
            .prefix(12)
            .map { frame in
                let index = frame["imageIndex"] as? Int ?? -1
                let image = images.indices.contains(index)
                    ? images[index]["name"] as? String ?? "?" : "?"
                let symbol = frame["symbol"] as? String
                    ?? "+\(frame["imageOffset"] as? Int ?? 0)"
                return "\(image) \(symbol)"
            }
            .joined(separator: "\n")
        return summary
    }

    private static func send(_ summary: Summary, to endpoint: URL) -> Bool {
        let payload: [String: String] = [
            "id": Telemetry.installID,
            "crash_ts": summary.crashTime,
            "version": summary.version,
            "os": summary.os,
            "exception": String(summary.exception.prefix(256)),
            "frames": String(summary.frames.prefix(4096)),
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BubbleSearch/\(Telemetry.appVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 10

        var succeeded = false
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            succeeded = (response as? HTTPURLResponse)?.statusCode == 200
            done.signal()
        }.resume()
        done.wait()
        return succeeded
    }
}
