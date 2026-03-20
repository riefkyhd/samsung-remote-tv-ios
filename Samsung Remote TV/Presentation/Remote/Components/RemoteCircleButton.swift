import SwiftUI
import UIKit

struct RemoteCircleButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
