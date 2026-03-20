import SwiftUI
import UIKit

struct RemoteView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel: RemoteViewModel

    init(viewModel: RemoteViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.07, blue: 0.10), Color(red: 0.11, green: 0.12, blue: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: 20) {
                        remoteBody
                        sidePanel
                    }
                    .padding(20)
                } else {
                    VStack(spacing: 16) {
                        remoteBody
                        sidePanel
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle(viewModel.tv.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.connectionColor)
                            .frame(width: 8, height: 8)
                        Text(viewModel.connectionLabel)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Button {
                        viewModel.sendKey(.KEY_POWER)
                    } label: {
                        Image(systemName: "power")
                            .foregroundStyle(.red)
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.8)
                            .onEnded { _ in
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.sendLongPressPower()
                            }
                    )

                    NavigationLink(destination: SettingsView(viewModel: SettingsViewModel(dependencies: dependencies))) {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .task {
            viewModel.connect()
            viewModel.loadApps()
        }
        .onDisappear {
            viewModel.disconnect()
        }
        .sheet(isPresented: $viewModel.isAppSheetPresented) {
            AppLauncherSheet(apps: viewModel.installedApps) { app in
                viewModel.launchApp(app)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showPinSheet) {
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
                        Text("Time remaining: \(viewModel.pinCountdown)s")
                            .font(.caption)
                    }

                    Section {
                        Button("Confirm") {
                            viewModel.submitPin()
                        }
                        .disabled(viewModel.pinCode.isEmpty || viewModel.isSubmittingPin || viewModel.isProbingVariants)

                        Button("Cancel", role: .destructive) {
                            viewModel.cancelPinEntry()
                        }
                    }

                    Section {
                        Text("This TV cannot be powered on remotely. Make sure the TV is already on.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .navigationTitle("TV PIN Pairing")
            }
            .presentationDetents([.medium])
        }
        .alert("Error", isPresented: $viewModel.showError, actions: {}) {
            Text(viewModel.errorMessage)
        }
    }

    private var remoteBody: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                RemoteCircleButton(icon: "house.fill", label: "Home") { viewModel.sendKey(.KEY_HOME) }
                RemoteCircleButton(icon: "rectangle.on.rectangle", label: "Source") { viewModel.sendKey(.KEY_SOURCE) }
                Button {
                    viewModel.sendKey(.KEY_POWER)
                } label: {
                    Circle()
                        .fill(Color.red.opacity(0.20))
                        .overlay(Circle().stroke(Color.red.opacity(0.8), lineWidth: 1.2))
                        .overlay(Image(systemName: "power").foregroundStyle(.red))
                        .frame(width: 56, height: 56)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.8)
                        .onEnded { _ in viewModel.sendLongPressPower() }
                )
            }

            DPadController { key in
                viewModel.sendKey(key)
            }
            .frame(width: 250)

            HStack(spacing: 12) {
                softButton("Return") { viewModel.sendKey(.KEY_RETURN) }
                softButton("Exit") { viewModel.sendKey(.KEY_EXIT) }
            }

            HStack(alignment: .top, spacing: 24) {
                VolumeControl { key in viewModel.sendKey(key) }
                ChannelControl { key in viewModel.sendKey(key) }
            }

            MediaControls(
                playPauseAction: { viewModel.togglePlayPause() },
                action: { key in viewModel.sendKey(key) }
            )

            ColorButtons { key in viewModel.sendKey(key) }
        }
        .padding(18)
        .frame(maxWidth: horizontalSizeClass == .regular ? 420 : .infinity)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
        )
    }

    private var sidePanel: some View {
        VStack(spacing: 14) {
            DisclosureGroup(isExpanded: $viewModel.numberPadVisible) {
                NumberPad { key in viewModel.sendKey(key) }
                    .padding(.top, 8)
            } label: {
                Text("Number Pad")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .tint(.white)

            HStack(spacing: 8) {
                softButton("Menu") { viewModel.sendKey(.KEY_MENU) }
                softButton("Guide") { viewModel.sendKey(.KEY_GUIDE) }
            }
            HStack(spacing: 8) {
                softButton("Tools") { viewModel.sendKey(.KEY_TOOLS) }
                softButton("Info") { viewModel.sendKey(.KEY_INFO) }
            }

            HStack(spacing: 8) {
                softButton("Hub") { viewModel.sendKey(.KEY_SMARTHUB) }
                softButton("HDMI") { viewModel.sendKey(.KEY_HDMI) }
            }

            Button("Open Apps") {
                viewModel.isAppSheetPresented = true
            }
            .buttonStyle(.borderedProminent)

            Button("Wake TV") {
                viewModel.wakeTV()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.tv.protocolType == .encrypted)
        }
        .padding(16)
        .frame(maxWidth: horizontalSizeClass == .regular ? 280 : .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )
        )
    }

    private func softButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }
        .buttonStyle(.bordered)
    }
}

#Preview {
    RemoteView(viewModel: RemoteViewModel(
        tv: SamsungTV(name: "Living Room TV", ipAddress: "192.168.1.12", macAddress: "AA:BB:CC:DD:EE:FF", model: "QLED", type: .tizen, protocolType: .modern),
        dependencies: AppDependencies()
    ))
}
