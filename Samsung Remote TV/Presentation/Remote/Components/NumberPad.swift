import SwiftUI
import UIKit

struct NumberPad: View {
    let action: (RemoteKey) -> Void

    private let keys: [RemoteKey] = [
        .KEY_1, .KEY_2, .KEY_3,
        .KEY_4, .KEY_5, .KEY_6,
        .KEY_7, .KEY_8, .KEY_9,
        .KEY_TTX_MIX, .KEY_0, .KEY_PRECH
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(keys, id: \.self) { key in
                Button(keyLabel(for: key)) {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    action(key)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(key.rawValue)
            }
        }
    }

    private func keyLabel(for key: RemoteKey) -> String {
        switch key {
        case .KEY_PRECH:
            return "Prev"
        case .KEY_TTX_MIX:
            return "TTX"
        default:
            return key.rawValue.replacingOccurrences(of: "KEY_", with: "")
        }
    }
}
