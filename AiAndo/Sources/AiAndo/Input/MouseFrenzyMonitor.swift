import AppKit
import Foundation

/// Samples the pointer while the overlay is up. Click-through panels never see mouse-moved events.
@MainActor
final class MouseFrenzyMonitor {
    private let model: OverlayModel
    private var tracker = MouseFrenzyTracker()
    private let clock = Clock()
    /// Uptime until which the caption stays after the last frantic sample.
    private var visibleUntil: TimeInterval?

    init(model: OverlayModel) {
        self.model = model
    }

    deinit {
        clock.invalidate()
    }

    func start() {
        guard !clock.isRunning else { return }
        tracker.reset()
        visibleUntil = nil
        clock.schedule { [weak self] in
            self?.tick()
        }
    }

    func stop() {
        clock.invalidate()
        tracker.reset()
        visibleUntil = nil
        model.dizzyLine = nil
    }

    private func tick() {
        let point = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        tracker.add(x: point.x, y: point.y, time: now)
        if tracker.isFrantic {
            visibleUntil = now + 1.1
            if model.dizzyLine == nil {
                model.dizzyLine = MouseDizzyCopy.line
            }
        } else if let visibleUntil, now >= visibleUntil {
            self.visibleUntil = nil
            model.dizzyLine = nil
        }
    }
}

/// Timer box that can be killed from `deinit` without hopping to the main actor.
private final class Clock: @unchecked Sendable {
    private var timer: Timer?

    var isRunning: Bool { timer != nil }

    func schedule(_ tick: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
}
