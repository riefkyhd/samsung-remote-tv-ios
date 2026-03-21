import SwiftUI
import UIKit

struct TrackpadView: View {
    let onKey: (RemoteKey) -> Void

    @State private var lastSentPosition: CGPoint = .zero
    @State private var isDragging = false

    private let sensitivity: CGFloat = 30
    private let bgColor = Color(.systemGray6)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )

            VStack(spacing: 4) {
                Image(systemName: "hand.point.up.left")
                    .foregroundStyle(.secondary)
                Text(L10n.text("remote.trackpad", "Trackpad"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .opacity(isDragging ? 0 : 0.5)
        }
        .frame(height: 180)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        lastSentPosition = value.location
                    }

                    let dx = value.location.x - lastSentPosition.x
                    let dy = value.location.y - lastSentPosition.y

                    if abs(dx) >= sensitivity {
                        let key: RemoteKey = dx > 0 ? .KEY_RIGHT : .KEY_LEFT
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        onKey(key)
                        lastSentPosition.x = value.location.x
                    }

                    if abs(dy) >= sensitivity {
                        let key: RemoteKey = dy > 0 ? .KEY_DOWN : .KEY_UP
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        onKey(key)
                        lastSentPosition.y = value.location.y
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    lastSentPosition = .zero
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onKey(.KEY_ENTER)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("remote.trackpad_label", "Trackpad Control"))
        .accessibilityHint(L10n.text("remote.trackpad_hint", "Swipe to move focus and tap to confirm."))
    }
}

#Preview {
    TrackpadView { key in
        print(key)
    }
    .padding()
}
