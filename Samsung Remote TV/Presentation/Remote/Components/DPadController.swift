import SwiftUI
import UIKit

struct DPadController: View {
    let action: (RemoteKey) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size * 0.45
            let centerSize = size * 0.34

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .stroke(Color.white.opacity(0.24), lineWidth: 1.2)

                Circle()
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    .padding(size * 0.17)

                Group {
                    Image(systemName: "chevron.up")
                        .offset(y: -size * 0.30)
                    Image(systemName: "chevron.down")
                        .offset(y: size * 0.30)
                    Image(systemName: "chevron.left")
                        .offset(x: -size * 0.30)
                    Image(systemName: "chevron.right")
                        .offset(x: size * 0.30)
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))

                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: centerSize, height: centerSize)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .overlay(
                        Text("OK")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                    )
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y
                        let distance = sqrt(dx * dx + dy * dy)

                        if distance < radius * 0.25 {
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                            action(.KEY_ENTER)
                            return
                        }

                        let angle = atan2(dy, dx)
                        switch angle {
                        case (-.pi / 4)...(.pi / 4):
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                            action(.KEY_RIGHT)
                        case (.pi / 4)...(3 * .pi / 4):
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                            action(.KEY_DOWN)
                        case (-3 * .pi / 4)...(-.pi / 4):
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                            action(.KEY_UP)
                        default:
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                            action(.KEY_LEFT)
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.text("remote.dpad_label", "D-Pad"))
            .accessibilityHint(L10n.text("remote.dpad_hint", "Tap a direction to navigate. Tap center to confirm."))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    DPadController { _ in }
        .frame(width: 220)
        .padding()
}
