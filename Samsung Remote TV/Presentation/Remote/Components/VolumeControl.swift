import SwiftUI
import UIKit

struct VolumeControl: View {
    let action: (RemoteKey) -> Void

    var body: some View {
        VStack(spacing: 10) {
            RemoteCircleButton(icon: "plus", label: L10n.text("remote.volume_up", "Volume Up")) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action(.KEY_VOLUP)
            }
            RemoteCircleButton(icon: "speaker.slash.fill", label: L10n.text("remote.mute", "Mute")) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action(.KEY_MUTE)
            }
            RemoteCircleButton(icon: "minus", label: L10n.text("remote.volume_down", "Volume Down")) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action(.KEY_VOLDOWN)
            }
        }
    }
}
