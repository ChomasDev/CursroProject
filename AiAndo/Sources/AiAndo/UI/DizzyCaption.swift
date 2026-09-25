import SwiftUI

/// Lower-third caption. White fill, hard black ring, tiny shake — TikTok subtitle, not the Dia type.
struct DizzyCaption: View {
    let text: String
    @State private var wobble = false

    private static let ring: [(CGFloat, CGFloat)] = [
        (-3, 0), (3, 0), (0, -3), (0, 3),
        (-2.2, -2.2), (2.2, -2.2), (-2.2, 2.2), (2.2, 2.2),
        (-3, -1.2), (3, -1.2), (-3, 1.2), (3, 1.2),
    ]

    var body: some View {
        VStack {
            Spacer()
            ZStack {
                ForEach(Array(Self.ring.enumerated()), id: \.offset) { _, point in
                    caption.foregroundStyle(.black).offset(x: point.0, y: point.1)
                }
                caption.foregroundStyle(.white)
            }
            .rotationEffect(.degrees(wobble ? 2.2 : -2.2))
            .offset(x: wobble ? 5 : -5, y: wobble ? -2 : 2)
            .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
            .padding(.horizontal, 48)
            .padding(.bottom, 118)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.16).repeatForever(autoreverses: true)) {
                wobble = true
            }
        }
    }

    private var caption: some View {
        Text(text)
            .font(.system(size: 34, weight: .black, design: .rounded))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .frame(maxWidth: 820)
    }
}
