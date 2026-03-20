import SwiftUI

struct ColorButtons: View {
    let action: (RemoteKey) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ColorButton(color: .red, label: "Red") { action(.KEY_RED) }
            ColorButton(color: .green, label: "Green") { action(.KEY_GREEN) }
            ColorButton(color: .yellow, label: "Yellow") { action(.KEY_YELLOW) }
            ColorButton(color: .blue, label: "Blue") { action(.KEY_BLUE) }
        }
    }
}

private struct ColorButton: View {
    let color: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.9))
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .accessibilityLabel(label)
    }
}
