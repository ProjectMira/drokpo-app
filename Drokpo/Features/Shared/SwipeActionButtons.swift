import SwiftUI

/// The pass/like circular buttons shown under the Discover deck and inside
/// the expanded profile sheet. Sized proportionally to screen width so they
/// read consistently across devices, with matching weight for both actions.
struct SwipeActionButtons: View {
    var onPass: () -> Void
    var onLike: () -> Void

    /// Vertical space deck cards must keep free at the bottom so their text
    /// never sits underneath these overlaid buttons (button diameter + the
    /// deck's bottom padding + breathing room).
    static let deckClearance: CGFloat = 112

    private var diameter: CGFloat {
        min(72, UIScreen.main.bounds.width * 0.17)
    }

    var body: some View {
        HStack {
            Spacer()
            button(systemImage: "xmark", tint: .accentColor, action: onPass)
            Spacer()
            button(systemImage: "heart.fill", tint: .brandRed, action: onLike)
            Spacer()
        }
    }

    private func button(systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.42, weight: .bold))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(.background).shadow(radius: 4))
                .foregroundStyle(tint)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
