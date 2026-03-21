import SwiftUI

struct DiscoveryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: DiscoveryViewModel
    @State private var discoveryTask: Task<Void, Never>?
    let onSelectTV: (SamsungTV) -> Void
    let onOpenSettings: (() -> Void)?

    init(
        viewModel: DiscoveryViewModel,
        onSelectTV: @escaping (SamsungTV) -> Void,
        onOpenSettings: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectTV = onSelectTV
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        Group {
            if viewModel.visibleDiscoveredTVs.isEmpty && viewModel.savedTVs.isEmpty && !viewModel.isScanning {
                ContentUnavailableView(
                    L10n.text("discovery.no_tvs_title", "No TVs Found"),
                    systemImage: "tv",
                    description: Text(L10n.text("discovery.no_tvs_description", "Ensure iPhone and TV are on the same Wi-Fi."))
                )
            } else {
                List {
                    if !viewModel.savedTVs.isEmpty {
                        Section(L10n.text("discovery.saved_section", "Saved TVs")) {
                            ForEach(viewModel.savedTVs) { tv in
                                tvRow(tv, isSaved: true)
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            viewModel.deleteSavedTV(tv)
                                        } label: {
                                            Label(L10n.text("common.delete", "Delete"), systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }

                    Section(L10n.text("discovery.discovered_section", "Discovered TVs")) {
                        if viewModel.visibleDiscoveredTVs.isEmpty {
                            Text(L10n.text("discovery.no_new_tvs", "No new TVs found on this scan."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.visibleDiscoveredTVs) { tv in
                                tvRow(tv, isSaved: false)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(L10n.text("discovery.navigation_title", "Samsung TV Remote"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let onOpenSettings {
                    Button {
                        onOpenSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(L10n.text("common.settings", "Settings"))
                    .accessibilityHint(L10n.text("discovery.settings_hint", "Opens app settings."))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.text("discovery.add_manually", "Add Manually")) {
                    viewModel.showManualSheet = true
                }
            }
        }
        .onAppear {
            viewModel.loadSavedTVs()
            startDiscoveryIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                startDiscoveryIfNeeded()
            case .background, .inactive:
                discoveryTask?.cancel()
                discoveryTask = nil
            @unknown default:
                break
            }
        }
        .onDisappear {
            discoveryTask?.cancel()
            discoveryTask = nil
        }
        .refreshable {
            await viewModel.scan()
            viewModel.loadSavedTVs()
        }
        .sheet(isPresented: $viewModel.showManualSheet) {
            NavigationStack {
                Form {
                    TextField(L10n.text("discovery.manual_ip_placeholder", "192.168.1.20"), text: $viewModel.manualIPAddress)
                        .keyboardType(.numbersAndPunctuation)
                    Button(L10n.text("common.connect", "Connect")) {
                        Task {
                            if let tv = await viewModel.connectManual() {
                                onSelectTV(tv)
                            }
                        }
                    }
                }
                .navigationTitle(L10n.text("discovery.manual_title", "Add TV by IP"))
            }
            .presentationDetents([.medium])
        }
        .alert(
            L10n.text("common.error", "Error"),
            isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            ),
            actions: {}
        ) {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private func tvRow(_ tv: SamsungTV, isSaved: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(isSaved ? Color.green.opacity(0.22) : Color.blue.opacity(0.20))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: isSaved ? "checkmark.tv.fill" : "tv.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSaved ? .green : .blue)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(tv.name)
                    .font(.headline)
                Text("\(tv.model) • \(tv.ipAddress)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(tv.protocolType.rawValue.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isSaved ? L10n.text("common.open", "Open") : L10n.text("common.connect", "Connect")) {
                onSelectTV(tv)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tv.name), \(tv.model), \(tv.ipAddress)")
    }

    private func startDiscoveryIfNeeded() {
        guard scenePhase == .active else { return }
        guard discoveryTask == nil else { return }
        discoveryTask = Task {
            await viewModel.startDiscovery()
            await MainActor.run {
                discoveryTask = nil
            }
        }
    }
}

#Preview {
    NavigationStack {
        DiscoveryView(
            viewModel: DiscoveryViewModel(dependencies: AppDependencies()),
            onSelectTV: { _ in }
        )
    }
}

#Preview("Dynamic Type") {
    NavigationStack {
        DiscoveryView(
            viewModel: DiscoveryViewModel(dependencies: AppDependencies()),
            onSelectTV: { _ in }
        )
        .dynamicTypeSize(.accessibility3)
    }
}
