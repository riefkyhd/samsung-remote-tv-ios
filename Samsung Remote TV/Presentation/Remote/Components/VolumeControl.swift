import SwiftUI
import UIKit

@MainActor
final class VolumeHoldRepeater {
    private let initialDelay: Duration
    private let repeatInterval: Duration
    private var repeatTask: Task<Void, Never>?
    private var activeKey: RemoteKey?
    private var generation: UInt64 = 0

    init(initialDelay: Duration = .milliseconds(320), repeatInterval: Duration = .milliseconds(180)) {
        self.initialDelay = initialDelay
        self.repeatInterval = repeatInterval
    }

    func press(_ key: RemoteKey, fire: @escaping (RemoteKey, Bool) -> Void) {
        guard key == .KEY_VOLUP || key == .KEY_VOLDOWN else {
            fire(key, false)
            return
        }
        guard activeKey != key else { return }

        activeKey = key
        generation &+= 1
        let token = generation
        repeatTask?.cancel()
        repeatTask = nil

        fire(key, false)
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

struct VolumeControl: View {
    let action: (RemoteKey, Bool) -> Void
    let onRelease: () -> Void
    @State private var holdRepeater = VolumeHoldRepeater()

    init(
        action: @escaping (RemoteKey, Bool) -> Void,
        onRelease: @escaping () -> Void = {}
    ) {
        self.action = action
        self.onRelease = onRelease
    }

    var body: some View {
        VStack(spacing: 10) {
            holdableButton(icon: "plus", label: L10n.text("remote.volume_up", "Volume Up"), key: .KEY_VOLUP)
            RemoteCircleButton(icon: "speaker.slash.fill", label: L10n.text("remote.mute", "Mute")) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action(.KEY_MUTE, false)
            }
            holdableButton(icon: "minus", label: L10n.text("remote.volume_down", "Volume Down"), key: .KEY_VOLDOWN)
        }
        .onDisappear {
            holdRepeater.release()
            onRelease()
        }
    }

    @ViewBuilder
    private func holdableButton(icon: String, label: String, key: RemoteKey) -> some View {
        RemoteCircleButton(icon: icon, label: label) {}
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        holdRepeater.press(key) { resolvedKey, isRepeat in
                            if !isRepeat {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            action(resolvedKey, isRepeat)
                        }
                    }
                    .onEnded { _ in
                        holdRepeater.release()
                        onRelease()
                    }
            )
    }
}
