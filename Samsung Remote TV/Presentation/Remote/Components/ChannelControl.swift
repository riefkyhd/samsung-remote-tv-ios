import SwiftUI

struct ChannelControl: View {
    let action: (RemoteKey) -> Void

    var body: some View {
        VStack(spacing: 10) {
            RemoteCircleButton(icon: "chevron.up", label: "Channel Up") { action(.KEY_CHUP) }
            RemoteCircleButton(icon: "list.bullet", label: "Channel List") { action(.KEY_CH_LIST) }
            RemoteCircleButton(icon: "chevron.down", label: "Channel Down") { action(.KEY_CHDOWN) }
        }
    }
}
