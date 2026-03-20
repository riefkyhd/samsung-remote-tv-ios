import SwiftUI

struct MediaControls: View {
    let playPauseAction: () -> Void
    let action: (RemoteKey) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                RemoteCircleButton(icon: "backward.fill", label: "Rewind") { action(.KEY_REWIND) }
                RemoteCircleButton(icon: "playpause.fill", label: "Play Pause") { playPauseAction() }
                RemoteCircleButton(icon: "forward.fill", label: "Fast Forward") { action(.KEY_FF) }
            }
            HStack(spacing: 12) {
                RemoteCircleButton(icon: "stop.fill", label: "Stop") { action(.KEY_STOP) }
                RemoteCircleButton(icon: "record.circle", label: "Record") { action(.KEY_REC) }
            }
        }
    }
}
