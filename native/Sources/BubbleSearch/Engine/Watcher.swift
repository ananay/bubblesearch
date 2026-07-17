import Foundation
import CoreServices

/// FSEvents watcher on ~/Library/Messages — fires (debounced) whenever
/// Messages writes to chat.db*, so the index can sync automatically.
final class ChatDBWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "bubblesearch.watcher")
    private var debounceTask: DispatchWorkItem?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        let dir = (Paths.chatDB as NSString).deletingLastPathComponent
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, pathsPtr, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ChatDBWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = pathsPtr.bindMemory(to: UnsafePointer<CChar>.self, capacity: count)
            for i in 0..<count {
                let path = String(cString: paths[i])
                if (path as NSString).lastPathComponent.hasPrefix("chat.db") {
                    watcher.scheduleSync()
                    break
                }
            }
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context,
            [dir] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // latency (seconds)
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func scheduleSync() {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.onChange() }
        debounceTask = task
        queue.asyncAfter(deadline: .now() + 1.0, execute: task)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
