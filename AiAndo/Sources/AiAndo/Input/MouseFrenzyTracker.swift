import Foundation

/// Copy shown when the pointer thrashes across the overlay.
enum MouseDizzyCopy {
    static let line = "Woooo cavallo calma che mi stai facendo venire mal di pancia"
}

/// Path length of the pointer inside a short window. Frantic = a lot of travel, not a normal move.
struct MouseFrenzyTracker {
    var window: TimeInterval = 0.7
    var distanceThreshold: Double = 2400

    private var samples: [Sample] = []

    struct Sample {
        var x: Double
        var y: Double
        var time: TimeInterval
    }

    mutating func add(x: Double, y: Double, time: TimeInterval) {
        if let last = samples.last {
            let dx = x - last.x
            let dy = y - last.y
            if dx * dx + dy * dy < 4 { return }
        }
        samples.append(Sample(x: x, y: y, time: time))
        let cutoff = time - window
        samples.removeAll { $0.time < cutoff }
    }

    var distance: Double {
        guard samples.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<samples.count {
            let dx = samples[index].x - samples[index - 1].x
            let dy = samples[index].y - samples[index - 1].y
            total += (dx * dx + dy * dy).squareRoot()
        }
        return total
    }

    var isFrantic: Bool { distance >= distanceThreshold }

    mutating func reset() {
        samples.removeAll()
    }
}
