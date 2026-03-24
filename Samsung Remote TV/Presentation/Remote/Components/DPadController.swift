import SwiftUI
import UIKit

@MainActor
final class DPadHoldRepeater {
    private let initialDelay: Duration
    private let repeatInterval: Duration
    private var repeatTask: Task<Void, Never>?
    private var activeKey: RemoteKey?
    private var generation: UInt64 = 0

    init(initialDelay: Duration = .milliseconds(280), repeatInterval: Duration = .milliseconds(115)) {
        self.initialDelay = initialDelay
        self.repeatInterval = repeatInterval
    }

    func press(_ key: RemoteKey, fire: @escaping (RemoteKey, Bool) -> Void) {
        guard activeKey != key else { return }
        activeKey = key
        generation &+= 1
        let token = generation
        repeatTask?.cancel()
        repeatTask = nil

        fire(key, false)

        guard key.isDirectional else { return }
        repeatTask = Task {
            do {
                try await Task.sleep(for: initialDelay)
                while !Task.isCancelled, self.generation == token, self.activeKey == key {
                    fire(key, true)
                    try await Task.sleep(for: repeatInterval)
                }
            } catch {
                return
            }
        }
    }

    func release() {
        generation &+= 1
        activeKey = nil
        repeatTask?.cancel()
        repeatTask = nil
    }
}

private extension RemoteKey {
    var isDirectional: Bool {
        switch self {
        case .KEY_UP, .KEY_DOWN, .KEY_LEFT, .KEY_RIGHT:
            return true
        default:
            return false
        }
    }
}

struct DPadController: View {
    let action: (RemoteKey, Bool) -> Void
    let onRelease: () -> Void
    @State private var pressedKey: RemoteKey?
    @State private var holdRepeater = DPadHoldRepeater()

    init(
        action: @escaping (RemoteKey, Bool) -> Void,
        onRelease: @escaping () -> Void = {}
    ) {
        self.action = action
        self.onRelease = onRelease
    }

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
                    .onChanged { value in
                        let key = resolveKey(
                            at: value.location,
                            center: center,
                            radius: radius
                        )
                        guard pressedKey != key else { return }
                        pressedKey = key
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        holdRepeater.press(key) { resolvedKey, isRepeat in
                            action(resolvedKey, isRepeat)
                        }
                    }
                    .onEnded { _ in
                        pressedKey = nil
                        holdRepeater.release()
                        onRelease()
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.text("remote.dpad_label", "D-Pad"))
            .accessibilityHint(L10n.text("remote.dpad_hint", "Tap a direction to navigate. Press and hold to repeat. Tap center to confirm."))
            .onDisappear {
                pressedKey = nil
                holdRepeater.release()
                onRelease()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func resolveKey(at location: CGPoint, center: CGPoint, radius: CGFloat) -> RemoteKey {
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        if distance < radius * 0.25 {
            return .KEY_ENTER
        }

        let angle = atan2(dy, dx)
        switch angle {
        case (-.pi / 4)...(.pi / 4):
            return .KEY_RIGHT
        case (.pi / 4)...(3 * .pi / 4):
            return .KEY_DOWN
        case (-3 * .pi / 4)...(-.pi / 4):
            return .KEY_UP
        default:
            return .KEY_LEFT
        }
    }
}

#Preview {
    DPadController { _, _ in }
        .frame(width: 220)
        .padding()
}
