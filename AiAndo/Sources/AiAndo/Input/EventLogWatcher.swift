import Foundation

/// Tails `~/.cursor/prompt-mirror/events.jsonl` and emits `SessionEvent`s.
/// On `start()` the last ~64KB are replayed, keeping only events with ts >= start - 5s
/// (so the prompt that cold-launched the app is caught); then new lines are tailed.
final class EventLogWatcher: SessionEventSource, @unchecked Sendable {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/prompt-mirror/events.jsonl")
    }

    let url: URL
    let events: AsyncStream<SessionEvent>

    private let continuation: AsyncStream<SessionEvent>.Continuation
    private let queue = DispatchQueue(label: "aiando.eventlogwatcher")

    // All state below is only touched on `queue`.
    private var running = false
    private var startTime: Double = 0
    private var offset: UInt64 = 0
    private var inode: UInt64?
    private var buffer = Data()
    private var skipPartialFirstLine = false
    private let replayBytes: UInt64 = 64 * 1024
    private var source: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    private var timer: DispatchSourceTimer?

    /// Events whose `ts` is older than `startTime - staleTolerance` are dropped.
    private let staleTolerance: Double = 5

    init(url: URL = EventLogWatcher.defaultURL) {
        self.url = url
        var cont: AsyncStream<SessionEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(512)) { cont = $0 }
        self.continuation = cont
    }

    deinit {
        // Best effort; sources hold no strong ref to self (weak captures).
        source?.cancel()
        timer?.cancel()
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.running else { return }
            self.running = true
            self.startTime = Date().timeIntervalSince1970
            self.buffer.removeAll()
            self.skipPartialFirstLine = false
            if let st = self.statFile() {
                self.inode = st.inode
                // Replay the tail; stale events are filtered by ts.
                self.offset = st.size > self.replayBytes ? st.size - self.replayBytes : 0
                self.skipPartialFirstLine = self.offset > 0
            } else {
                self.inode = nil
                self.offset = 0
            }
            self.attachSource()
            self.poll()
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 0.25, repeating: 0.25, leeway: .milliseconds(50))
            t.setEventHandler { [weak self] in self?.poll() }
            t.resume()
            self.timer = t
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            self.running = false
            self.detachSource()
            self.timer?.cancel()
            self.timer = nil
        }
    }

    /// Ends the `events` stream permanently.
    func finish() {
        stop()
        queue.async { [continuation] in continuation.finish() }
    }

    // MARK: - File watching (queue only)

    private func attachSource() {
        detachSource()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.extend, .write, .delete, .rename], queue: queue)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            let mask = src.data
            if mask.contains(.delete) || mask.contains(.rename) {
                self.detachSource() // poll() will reattach when the new file appears
            }
            self.poll()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func detachSource() {
        source?.cancel() // cancel handler closes the fd
        source = nil
        watchedFD = -1
    }

    private func statFile() -> (inode: UInt64, size: UInt64)? {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        return (UInt64(st.st_ino), UInt64(st.st_size))
    }

    private func poll() {
        guard running else { return }
        guard let st = statFile() else {
            // File missing: wait for it to be (re)created; read it from the start then.
            if source != nil { detachSource() }
            inode = nil
            offset = 0
            buffer.removeAll()
            return
        }
        if inode != st.inode {
            // New or rotated file: everything in it is new.
            inode = st.inode
            offset = 0
            buffer.removeAll()
            skipPartialFirstLine = false
            attachSource()
        } else if source == nil {
            attachSource()
        }
        if st.size < offset {
            // Truncated.
            offset = 0
            buffer.removeAll()
            skipPartialFirstLine = false
        }
        guard st.size > offset else { return }
        readNewData()
    }

    private func readNewData() {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.readToEnd(), !data.isEmpty else { return }
            offset += UInt64(data.count)
            buffer.append(data)
        } catch {
            return
        }
        if skipPartialFirstLine {
            guard let nl = buffer.firstIndex(of: 0x0A) else { return }
            buffer.removeSubrange(buffer.startIndex...nl)
            skipPartialFirstLine = false
        }
        // Emit complete lines only; keep trailing partial line buffered.
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if let event = decode(line) { continuation.yield(event) }
        }
        if buffer.count > 4_000_000 { buffer.removeAll() } // runaway guard
    }

    // MARK: - Decoding

    private func decode(_ line: Data) -> SessionEvent? {
        guard !line.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return nil }
        let ts = (obj["ts"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
        if ts < startTime - staleTolerance { return nil }
        return Self.event(from: obj)
    }

    /// Maps one decoded hook log object to a `SessionEvent`. Exposed for tests/fixtures.
    static func event(from obj: [String: Any]) -> SessionEvent? {
        func str(_ k: String) -> String? {
            guard let s = obj[k] as? String, !s.isEmpty else { return nil }
            return s
        }
        let text = (obj["text"] as? String) ?? ""
        let duration = (obj["duration_ms"] as? NSNumber)?.intValue
        let tool = str("tool") ?? "unknown"
        let kind = str("kind") ?? ""
        switch kind {
        case "prompt":
            let ts = (obj["ts"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
            let id = str("generation_id") ?? str("id") ?? UUID().uuidString
            return .started(PromptSession(
                id: id,
                conversationId: str("conversation_id"),
                prompt: text,
                startedAt: Date(timeIntervalSince1970: ts),
                model: str("model")))
        case "thought": return .thought(text)
        case "tool_start": return .toolStarted(name: tool)
        case "tool_end": return .toolFinished(name: tool, durationMs: duration, failed: false)
        case "tool_fail": return .toolFinished(name: tool, durationMs: duration, failed: true)
        case "response": return .response(text)
        case "stop": return .stopped(durationMs: duration)
        default: return nil
        }
    }
}
