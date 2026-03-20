import SwiftUI

struct SmartViewPairingView: View {
    @ObservedObject var client: SmartViewSDKClient
    @State private var pin = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("Enter PIN shown on TV")
                .font(.title2.bold())

            Text("A 4-digit PIN is displayed on your Samsung TV screen.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("PIN", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .onChange(of: pin) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    pin = String(digits.prefix(4))
                }

            Button("Confirm") {
                Task {
                    do {
                        try await client.submitPin(pin)
                        dismiss()
                    } catch {
                        // Keep sheet open; state error is surfaced by client/repository.
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(pin.count != 4)

            Button("Cancel", role: .destructive) {
                client.disconnect()
                dismiss()
            }

            Text("This TV cannot be powered on remotely.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .padding(32)
    }
}

