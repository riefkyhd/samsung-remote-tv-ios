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
                        Text(tv.name)
                        Spacer()
                        Button("Forget Token", role: .destructive) {
                            viewModel.forgetToken(for: tv)
                        }
                        .font(.caption)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.delete(tv: tv)
                        } label: {
                            Label("Delete", systemImage: "trash")
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
