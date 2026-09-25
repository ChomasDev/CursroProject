import SwiftUI

/// Visual constants for the overlay (Dia-inspired: soft aurora, glass, big elegant type).
enum AA {
    static let pink = Color(red: 1.00, green: 0.36, blue: 0.64)
    static let violet = Color(red: 0.50, green: 0.38, blue: 1.00)
    static let orange = Color(red: 1.00, green: 0.62, blue: 0.26)
    static let cyan = Color(red: 0.26, green: 0.84, blue: 1.00)
    static let mint = Color(red: 0.36, green: 0.95, blue: 0.70)
    static let ink = Color(red: 0.05, green: 0.03, blue: 0.10)

    static let cornerRadius: CGFloat = 30

    static var hot: LinearGradient {
        LinearGradient(colors: [pink, orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var cool: LinearGradient {
        LinearGradient(colors: [cyan, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// Single accent used for numbers in the beats (soft green → cyan).
    static var accent: LinearGradient {
        LinearGradient(colors: [Color(red: 0.55, green: 1.0, blue: 0.78), Color(red: 0.45, green: 0.90, blue: 1.0)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var aurora: LinearGradient {
        LinearGradient(colors: [cyan, violet, pink, orange], startPoint: .leading, endPoint: .trailing)
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Italian number formatting ("48.213", "3,62 €").
enum Fmt {
    private static let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func int(_ v: Double) -> String {
        intFormatter.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))"
    }

    static func euro(_ v: Double) -> String {
        (decimalFormatter.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)) + " €"
    }

    static func seconds(_ v: Double) -> String {
        if v >= 60 {
            let m = Int(v) / 60
            let s = Int(v) % 60
            return "\(m)m \(s)s"
        }
        return String(format: "%.1fs", v).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Glass card

struct GlassCard: ViewModifier {
    var radius: CGFloat = 22
    var tint: Color = .white

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.10), tint.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.04), .white.opacity(0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }
}

extension View {
    func glassCard(radius: CGFloat = 22, tint: Color = .white) -> some View {
        modifier(GlassCard(radius: radius, tint: tint))
    }
}

// MARK: - Blur transition

struct BlurFadeModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    let scale: CGFloat
    let y: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(y: y)
    }
}

extension AnyTransition {
    /// Dia-like: blurry + transparent + slightly lower → sharp.
    static var blurRise: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurFadeModifier(radius: 18, opacity: 0, scale: 0.97, y: 18),
                identity: BlurFadeModifier(radius: 0, opacity: 1, scale: 1, y: 0)
            ),
            removal: .modifier(
                active: BlurFadeModifier(radius: 16, opacity: 0, scale: 1.02, y: -14),
                identity: BlurFadeModifier(radius: 0, opacity: 1, scale: 1, y: 0)
            )
        )
    }

    static var popIn: AnyTransition {
        .modifier(
            active: BlurFadeModifier(radius: 6, opacity: 0, scale: 0.85, y: 8),
            identity: BlurFadeModifier(radius: 0, opacity: 1, scale: 1, y: 0)
        )
    }
}

// MARK: - Staggered appearance

struct StaggeredAppear: ViewModifier {
    let index: Int
    var step: Double = 0.09
    var base: Double = 0.05
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .modifier(BlurFadeModifier(
                radius: shown ? 0 : 12, opacity: shown ? 1 : 0, scale: shown ? 1 : 0.96, y: shown ? 0 : 16
            ))
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.82).delay(base + Double(index) * step)) {
                    shown = true
                }
            }
    }
}

extension View {
    func staggered(_ index: Int, step: Double = 0.09, base: Double = 0.05) -> some View {
        modifier(StaggeredAppear(index: index, step: step, base: base))
    }
}

// MARK: - Pulsing dot

struct PulsingDot: View {
    var color: Color = AA.pink
    var pulsing: Bool = true
    var size: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.45))
                .frame(width: size, height: size)
                .scaleEffect(pulse && pulsing ? 2.6 : 1)
                .opacity(pulse && pulsing ? 0 : 0.8)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.8), radius: 4)
        }
        .frame(width: size * 2.6, height: size * 2.6)
        .onAppear {
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

// MARK: - Counting number

/// A number that counts up from 0 (or from its previous value) with rolling digits.
struct CountingNumber: View {
    let value: Double
    var format: (Double) -> String = { Fmt.int($0) }
    var duration: Double = 1.2
    @State private var shown: Double = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        Text(format(shown))
            .contentTransition(.numericText(value: shown))
            .monospacedDigit()
            .onAppear { run(to: value) }
            .onChange(of: value) { run(to: value) }
            .onDisappear { task?.cancel() }
    }

    private func run(to target: Double) {
        task?.cancel()
        let start = shown
        let steps = 26
        task = Task { @MainActor in
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: UInt64(duration / Double(steps) * 1_000_000_000))
                if Task.isCancelled { return }
                let p = Double(i) / Double(steps)
                let eased = 1 - pow(1 - p, 3)
                withAnimation(.snappy(duration: 0.18)) {
                    shown = start + (target - start) * eased
                }
            }
        }
    }
}
