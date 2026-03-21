import SwiftUI
import UIKit

struct ChannelControl: View {
    let action: (RemoteKey) -> Void

    var body: some View {
        VStack(spacing: 10) {
            RemoteCircleButton(icon: "chevron.up", label: L10n.text("remote.channel_up", "Channel Up")) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action(.KEY_CHUP)
            }
            RemoteCircleButton(icon: "list.bullet", label: L10n.text("remote.channel_list", "Channel List")) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action(.KEY_CH_LIST)
            }
            RemoteCircleButton(icon: "chevron.down", label: L10n.text("remote.channel_down", "Channel Down")) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action(.KEY_CHDOWN)
            }
        }
    }
}
