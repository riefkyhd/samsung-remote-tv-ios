import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @AppStorage("colorScheme") private var colorScheme = "system"

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            Section(L10n.text("settings.saved_tvs_section", "Saved TVs")) {
                ForEach(viewModel.savedTVs) { tv in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tv.name)
                            Text(L10n.text("settings.saved_tv_help", "Forget Pairing clears token/SPC data. Remove Device also deletes this saved TV."))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(viewModel.forgetPairingButtonTitle(for: tv)) {
                            viewModel.forgetPairing(tv)
                        }
                        .font(.caption)
                        .foregroundStyle(viewModel.isPairingCleared(for: tv) ? .green : .accentColor)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.removeDevice(tv)
                        } label: {
                            Label(L10n.text("settings.remove_device", "Remove Device"), systemImage: "trash")
                        }
                    }
                }
            }

            Section(L10n.text("settings.appearance_section", "Appearance")) {
                Picker(L10n.text("settings.color_scheme", "Color Scheme"), selection: $colorScheme) {
                    Text(L10n.text("settings.color_scheme_system", "System")).tag("system")
                    Text(L10n.text("settings.color_scheme_light", "Light")).tag("light")
                    Text(L10n.text("settings.color_scheme_dark", "Dark")).tag("dark")
                }
            }

            Section(L10n.text("settings.app_identity_section", "App Identity")) {
                TextField(L10n.text("settings.remote_name_placeholder", "Remote Name"), text: $viewModel.remoteName)
                Button(L10n.text("settings.save_remote_name", "Save Remote Name")) {
                    viewModel.saveRemoteName()
                }
            }

            Section(L10n.text("settings.about_section", "About")) {
                Text("\(L10n.text("settings.version", "Version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                Link(L10n.text("settings.samsung_developer_link", "Samsung Developer"), destination: URL(string: "https://developer.samsung.com/smarttv")!)
            }
        }
        .navigationTitle(L10n.text("common.settings", "Settings"))
        .task {
            viewModel.load()
        }
        .alert(
            viewModel.alertTitle,
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

#Preview("Dynamic Type") {
    NavigationStack {
        SettingsView(viewModel: SettingsViewModel(dependencies: AppDependencies()))
            .dynamicTypeSize(.accessibility3)
    }
}
