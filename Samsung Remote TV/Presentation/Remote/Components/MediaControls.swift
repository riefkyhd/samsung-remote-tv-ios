import SwiftUI
import UIKit

struct MediaControls: View {
    let playPauseAction: () -> Void
    let action: (RemoteKey) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                RemoteCircleButton(icon: "backward.fill", label: "Rewind") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action(.KEY_REWIND)
                }
                RemoteCircleButton(icon: "playpause.fill", label: "Play Pause") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    playPauseAction()
                }
                RemoteCircleButton(icon: "forward.fill", label: "Fast Forward") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action(.KEY_FF)
                }
            }
            HStack(spacing: 12) {
                RemoteCircleButton(icon: "stop.fill", label: "Stop") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action(.KEY_STOP)
                }
                RemoteCircleButton(icon: "record.circle", label: "Record") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action(.KEY_REC)
                }
            }
        }
    }
}
