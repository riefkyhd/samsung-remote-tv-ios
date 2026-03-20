import SwiftUI

struct VolumeControl: View {
    let action: (RemoteKey) -> Void

    var body: some View {
        VStack(spacing: 10) {
            RemoteCircleButton(icon: "plus", label: "Volume Up") { action(.KEY_VOLUP) }
            RemoteCircleButton(icon: "speaker.slash.fill", label: "Mute") { action(.KEY_MUTE) }
            RemoteCircleButton(icon: "minus", label: "Volume Down") { action(.KEY_VOLDOWN) }
        }
    }
}
