import AppKit
import Foundation

/// Wires Cursor events → roast stream → overlay.
@MainActor
final class Coordinator {
    private let model: OverlayModel
    private let panel: OverlayPanelController
    private let source: SessionEventSource
    private let service: RoastService

    private var tracker = SessionTracker()
    private var eventsTask: Task<Void, Never>?
    private var roastTask: Task<Void, Never>?
    private var introTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?

    private let introSeconds: Double = 2.6

    /// `AIANDO_USER` wins. Otherwise the macOS short username.
    private static func displayName() -> String {
        let env = ProcessInfo.processInfo.environment["AIANDO_USER"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty { return String(env.prefix(24)) }
        let user = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return user.isEmpty ? "anon" : String(user.prefix(24))
    }

    init(model: OverlayModel, panel: OverlayPanelController, source: SessionEventSource, service: RoastService) {
        self.model = model
        self.panel = panel
        self.source = source
        self.service = service
        model.onDismiss = { [weak self] in self?.close() }
    }

    func start() {
        source.start()
        let stream = source.events
        eventsTask = Task { [weak self] in
            for await event in stream {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: SessionEvent) {
        if case .started(let session) = event {
            begin(session)
            return
        }
        guard model.session != nil, model.phase != .idle else { return }

        tracker.consume(event)
        model.summary = tracker.summary()
        if let line = SessionTracker.activity(for: event) {
            model.activity = line
        }
        if case .stopped = event {
            model.agentFinished = true
            clockTask?.cancel()
            maybeFinish()
        }
    }

    private func begin(_ session: PromptSession) {
        roastTask?.cancel()
        introTask?.cancel()
        clockTask?.cancel()

        tracker = SessionTracker()
        tracker.begin(session)
        model.reset(for: session)
        model.activity = SessionTracker.activity(for: .started(session)) ?? ""
        panel.show()

        introTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.introSeconds ?? 2.6))
            guard let self, !Task.isCancelled, self.model.phase == .intro else { return }
            self.model.phase = .roasting
        }

        // Keep the live summary (elapsed time) ticking while the agent works.
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.model.summary = self.tracker.summary()
            }
        }

        let request = RoastRequest(
            sessionId: session.id,
            conversationId: session.conversationId,
            user: Self.displayName(),
            prompt: session.prompt,
            tokenCount: estimateTokens(session.prompt),
            model: session.model
        )
        let service = self.service
        roastTask = Task { [weak self] in
            do {
                for try await update in service.roast(request) {
                    guard let self, !Task.isCancelled else { return }
                    self.model.apply(update)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.model.errorMessage = "Il server è andato a fumare 🚬 (\(error.localizedDescription))"
            }
            guard let self, !Task.isCancelled else { return }
            self.model.roastFinished = true
            self.maybeFinish()
        }
    }

    /// The UI switches to `.summary` itself once its slow playback has caught up;
    /// here we only freeze the final numbers.
    private func maybeFinish() {
        guard model.agentFinished, model.roastFinished else { return }
        model.summary = tracker.summary()
    }

    private func close() {
        roastTask?.cancel()
        introTask?.cancel()
        clockTask?.cancel()
        panel.hide()
    }
}
