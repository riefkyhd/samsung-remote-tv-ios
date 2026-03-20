import SwiftUI

struct DiscoveryView: View {
    @State private var viewModel: DiscoveryViewModel
    let onSelectTV: (SamsungTV) -> Void

    init(viewModel: DiscoveryViewModel, onSelectTV: @escaping (SamsungTV) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectTV = onSelectTV
    }

    var body: some View {
        Group {
            if viewModel.discoveredTVs.isEmpty && viewModel.savedTVs.isEmpty && !viewModel.isScanning {
                ContentUnavailableView("No TVs Found", systemImage: "tv", description: Text("Ensure iPhone and TV are on the same Wi-Fi."))
            } else {
                List {
                    if !viewModel.savedTVs.isEmpty {
                        Section("Saved TVs") {
                            ForEach(viewModel.savedTVs) { tv in
                                tvRow(tv)
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            viewModel.deleteSavedTV(tv)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }

                    Section("Discovered TVs") {
                        ForEach(viewModel.discoveredTVs) { tv in
                            tvRow(tv)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Samsung TV Remote")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Manually") {
                    viewModel.showManualSheet = true
                }
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isScanning {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.largeTitle)
                    .padding(.top, 8)
                    .symbolEffect(.pulse, isActive: true)
            }
        }
        .task {
            viewModel.loadSavedTVs()
            await viewModel.startDiscovery()
        }
        .refreshable {
            await viewModel.scan()
            viewModel.loadSavedTVs()
        }
        .sheet(isPresented: $viewModel.showManualSheet) {
            NavigationStack {
                Form {
                    TextField("192.168.1.20", text: $viewModel.manualIPAddress)
                        .keyboardType(.numbersAndPunctuation)
                    Button("Connect") {
                        Task {
                            await viewModel.connectManual()
                        }
                    }
                }
                .navigationTitle("Add TV by IP")
            }
            .presentationDetents([.medium])
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

    private func tvRow(_ tv: SamsungTV) -> some View {
        Button {
            onSelectTV(tv)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tv.name)
                        .font(.headline)
                    Text("\(tv.model) • \(tv.ipAddress)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(tv.protocolType.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
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
