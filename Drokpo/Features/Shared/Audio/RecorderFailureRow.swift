import AVFoundation
import SwiftUI

/// Replaces a composer's input while its `AudioRecorder` is `.failed`: the
/// reason, a shortcut to the app's Settings page when mic access is off, and a
/// dismiss button back to the normal input so typing keeps working.
struct RecorderFailureRow: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if AVAudioApplication.shared.recordPermission == .denied,
               let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link("Settings", destination: settingsURL)
                    .font(.caption.bold())
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
    }
}
