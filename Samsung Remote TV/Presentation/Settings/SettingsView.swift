import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @AppStorage("colorScheme") private var colorScheme = "system"

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            Section("Saved TVs") {
                ForEach(viewModel.savedTVs) { tv in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tv.name)
                            Text("Forget Pairing clears token/SPC data. Remove Device also deletes this saved TV.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Forget Pairing") {
                            viewModel.forgetPairing(tv)
                        }
                        .font(.caption)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.removeDevice(tv)
                        } label: {
                            Label("Remove Device", systemImage: "trash")
                        }
                    }
                }
            }

            Section("Appearance") {
                Picker("Color Scheme", selection: $colorScheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }

            Section("App Identity") {
                TextField("Remote Name", text: $viewModel.remoteName)
                Button("Save Remote Name") {
                    viewModel.saveRemoteName()
                }
            }

            Section("About") {
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                Link("Samsung Developer", destination: URL(string: "https://developer.samsung.com/smarttv")!)
            }
        }
        .navigationTitle("Settings")
        .task {
            viewModel.load()
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            ),
            actions: {}
        ) {
            Text(viewModel.alertMessage ?? "")
        }
    }
}

#Preview {
    SettingsView(viewModel: SettingsViewModel(dependencies: AppDependencies()))
}
