import SwiftUI
import UIKit

struct ColorButtons: View {
    let action: (RemoteKey) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ColorButton(color: .red, label: L10n.text("remote.color_red", "Red")) { action(.KEY_RED) }
            ColorButton(color: .green, label: L10n.text("remote.color_green", "Green")) { action(.KEY_GREEN) }
            ColorButton(color: .yellow, label: L10n.text("remote.color_yellow", "Yellow")) { action(.KEY_YELLOW) }
            ColorButton(color: .blue, label: L10n.text("remote.color_blue", "Blue")) { action(.KEY_BLUE) }
        }
    }
}

private struct ColorButton: View {
    let color: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Text(label)
        }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.9))
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .accessibilityLabel(label)
    }
}
