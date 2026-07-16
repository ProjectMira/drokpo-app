import SwiftUI

/// The action buttons floating under the Discover deck and inside the
/// expanded profile sheet: undo · pass · like · share. Pass/like are the
/// primary pair; undo and share render smaller and only when their action is
/// provided (the expanded profile sheet shows just pass/like — share lives in
/// its toolbar). Sized proportionally to screen width so they read
/// consistently across devices.
struct SwipeActionButtons: View {
    /// Rewind the last swipe; the button is hidden when nil.
    var onUndo: (() -> Void)? = nil
    var undoDisabled = false
    var onPass: () -> Void
    var onLike: () -> Void
    /// Share the top card; the button is hidden when nil.
    var onShare: (() -> Void)? = nil
    var shareDisabled = false

    /// Vertical space deck cards must keep free at the bottom so their text
    /// never sits underneath these overlaid buttons (button diameter + the
    /// deck's bottom padding + breathing room).
    static let deckClearance: CGFloat = 112

    private var diameter: CGFloat {
        min(72, UIScreen.main.bounds.width * 0.17)
    }

    private var smallDiameter: CGFloat {
        diameter * 0.72
    }

    var body: some View {
        HStack(spacing: 20) {
            if let onUndo {
                button(systemImage: "arrow.uturn.backward", tint: .orange, diameter: smallDiameter, disabled: undoDisabled, action: onUndo)
                    .accessibilityLabel("Undo last swipe")
            }
            button(systemImage: "xmark", tint: .accentColor, diameter: diameter, action: onPass)
                .accessibilityLabel("Pass")
            button(systemImage: "heart.fill", tint: .brandRed, diameter: diameter, action: onLike)
                .accessibilityLabel("Like")
            if let onShare {
                button(systemImage: "square.and.arrow.up", tint: .accentColor, diameter: smallDiameter, disabled: shareDisabled, action: onShare)
                    .accessibilityLabel("Share")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func button(
        systemImage: String, tint: Color, diameter: CGFloat, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.42, weight: .bold))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(.background).shadow(radius: 4))
                .foregroundStyle(tint)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
