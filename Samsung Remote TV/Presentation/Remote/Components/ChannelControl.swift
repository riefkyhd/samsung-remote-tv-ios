import SwiftUI
import UIKit

struct ChannelControl: View {
    let action: (RemoteKey) -> Void

    var body: some View {
        VStack(spacing: 10) {
            RemoteCircleButton(icon: "chevron.up", label: "Channel Up") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action(.KEY_CHUP)
            }
            RemoteCircleButton(icon: "list.bullet", label: "Channel List") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action(.KEY_CH_LIST)
            }
            RemoteCircleButton(icon: "chevron.down", label: "Channel Down") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action(.KEY_CHDOWN)
            }
        }
    }
}
