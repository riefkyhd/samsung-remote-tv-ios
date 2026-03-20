import SwiftUI

struct SpcPairingView: View {
    @State private var viewModel: SpcPairingViewModel
    let onCancel: () -> Void
    let onSuccess: () -> Void
    let onTimeout: () -> Void

    init(
        viewModel: SpcPairingViewModel,
        onCancel: @escaping () -> Void,
        onSuccess: @escaping () -> Void,
        onTimeout: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onCancel = onCancel
        self.onSuccess = onSuccess
        self.onTimeout = onTimeout
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter PIN shown on your TV")
                        .font(.headline)
                    Text("A PIN code is displayed on your Samsung TV screen. Enter it below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("PIN") {
                    if viewModel.isProbingVariants {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Detecting TV protocol variant…")
                                .font(.subheadline)
                        }
                    }
                    TextField("1234", text: $viewModel.pinCode)
                        .keyboardType(.numberPad)
                    Text("Time remaining: \(viewModel.countdown)s")
                        .font(.caption)
                }

                Section {
                    Button("Confirm") {
                        Task {
                            await viewModel.submit(onSuccess: onSuccess)
                        }
                    }
                    .disabled(viewModel.pinCode.count < 4 || viewModel.isSubmitting || viewModel.isProbingVariants)

                    Button("Cancel", role: .destructive) {
                        viewModel.cancelCountdown()
                        onCancel()
                    }
                }

                Section {
                    Text("This TV cannot be powered on remotely. Make sure the TV is already on before connecting.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("TV PIN Pairing")
            .onAppear {
                viewModel.startCountdown(onTimeout: {
                    onTimeout()
                })
            }
            .alert(
                "Pairing Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                ),
                actions: {}
            ) {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
