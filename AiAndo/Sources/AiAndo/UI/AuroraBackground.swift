import AppKit
import SwiftUI

/// Slow, soft, animated aurora (MeshGradient on macOS 15, blurred Canvas blobs on 14).
struct AuroraBackground: View {
    /// 0 = calm, 1 = more vivid/fast (used during intro).
    var energy: Double = 0.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate * (0.12 + 0.10 * energy)
            Group {
                if #available(macOS 15, *) {
                    MeshAurora(t: t)
                } else {
                    CanvasAurora(t: t)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

@available(macOS 15, *)
private struct MeshAurora: View {
    let t: Double

    var body: some View {
        let s = { (phase: Double, amp: Double) -> Float in Float(sin(t + phase) * amp) }
        let c = { (phase: Double, amp: Double) -> Float in Float(cos(t * 0.8 + phase) * amp) }
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5 + s(0.3, 0.2), 0], [1, 0],
                [0, 0.5 + c(1.1, 0.18)], [0.5 + s(2.0, 0.22), 0.5 + c(0.4, 0.2)], [1, 0.5 + s(2.7, 0.18)],
                [0, 1], [0.5 + c(3.3, 0.22), 1], [1, 1],
            ],
            colors: [
                AA.violet, AA.pink.opacity(0.9), AA.orange.opacity(0.85),
                AA.cyan.opacity(0.8), AA.violet.opacity(0.55), AA.pink,
                AA.ink, AA.violet.opacity(0.8), AA.cyan.opacity(0.7),
            ],
            smoothsColors: true
        )
    }
}

private struct CanvasAurora: View {
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(AA.ink))
            ctx.addFilter(.blur(radius: min(size.width, size.height) * 0.16))
            let blobs: [(Color, Double, Double, Double)] = [
                (AA.violet, 0.0, 0.55, 0.55),
                (AA.pink, 1.7, 0.50, 0.45),
                (AA.orange, 3.1, 0.40, 0.40),
                (AA.cyan, 4.4, 0.45, 0.42),
            ]
            for (i, blob) in blobs.enumerated() {
                let (color, phase, rx, radius) = blob
                let cx = 0.5 + cos(t * (0.7 + Double(i) * 0.13) + phase) * rx * 0.6
                let cy = 0.5 + sin(t * (0.9 - Double(i) * 0.11) + phase * 1.3) * 0.38
                let r = radius * max(size.width, size.height) * (0.85 + 0.15 * sin(t + phase))
                let rect = CGRect(x: cx * size.width - r / 2, y: cy * size.height - r / 2, width: r, height: r)
                ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.85)))
            }
        }
    }
}

/// Fine film grain.
struct NoiseOverlay: View {
    var opacity: Double = 0.07

    static let image: NSImage = {
        let w = 180, h = 180
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        var rng = SystemRandomNumberGenerator()
        for i in 0..<(w * h) {
            let v = UInt8.random(in: 0...255, using: &rng)
            pixels[i * 4] = v
            pixels[i * 4 + 1] = v
            pixels[i * 4 + 2] = v
            pixels[i * 4 + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return NSImage(cgImage: cg, size: NSSize(width: w / 2, height: h / 2))
    }()

    var body: some View {
        Image(nsImage: Self.image)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .blendMode(.overlay)
            .allowsHitTesting(false)
    }
}
