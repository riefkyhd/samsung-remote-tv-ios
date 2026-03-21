import SwiftUI
import UIKit

struct RemoteView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel: RemoteViewModel
    @State private var showTrackpad = false
    @State private var isPinInputActive = false
    @State private var isSettingsPresented = false

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
                    VStack(spacing: 10) {
                        inlineErrorBanner
                        HStack(alignment: .top, spacing: 20) {
                            remoteBody
                            sidePanel
                        }
                    }
                    .padding(20)
                } else {
                    VStack(spacing: 16) {
                        inlineErrorBanner
                        remoteBody
                        sidePanel
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .blur(radius: shouldBlurRemote ? 2.5 : 0)
            .animation(.easeInOut(duration: 0.2), value: shouldBlurRemote)

            if shouldBlurRemote {
                connectionOverlay
            }
        }
        .navigationTitle(viewModel.tv.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(viewModel.connectionColor)
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(viewModel.connectionLabel)

                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .onAppear {
            viewModel.connect()
            viewModel.loadQuickLaunchApps()
        }
        .onDisappear {
            viewModel.handleRemoteDisappear(shouldDisconnect: !isSettingsPresented)
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView(viewModel: SettingsViewModel(dependencies: dependencies))
            }
        }
        .sheet(isPresented: $viewModel.isAppSheetPresented) {
            AppLauncherSheet(apps: viewModel.quickLaunchApps) { app in
                viewModel.launchApp(app)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showPinSheet) {
            pinSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: viewModel.showPinSheet) { _, shown in
            if !shown {
                isPinInputActive = false
            }
        }
    }

    private var remoteBody: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                RemoteCircleButton(icon: "house.fill", label: "Home") {
                    haptic(.light)
                    viewModel.sendKey(.KEY_HOME)
                }
                RemoteCircleButton(icon: "rectangle.on.rectangle", label: "Source") {
                    haptic(.light)
                    viewModel.sendKey(.KEY_SOURCE)
                }
                Button {
                    haptic(.heavy)
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
                        .onEnded { _ in
                            haptic(.heavy)
                            viewModel.sendLongPressPower()
                        }
                )
            }

            if viewModel.capabilities.trackpad {
                Picker("Mode", selection: $showTrackpad) {
                    Text("Remote").tag(false)
                    Text("Trackpad").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 8)
            } else {
                Text(viewModel.capabilityMessage(for: .trackpad))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }

            if viewModel.capabilities.trackpad && showTrackpad {
                TrackpadView { key in
                    viewModel.sendKey(key)
                }
            } else {
                DPadController { key in
                    viewModel.sendKey(key)
                }
                .frame(width: 250)
            }

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
            .disabled(!viewModel.capabilities.mediaTransport)
            .opacity(viewModel.capabilities.mediaTransport ? 1 : 0.5)

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
            .disabled(!viewModel.capabilities.numberPad)
            .opacity(viewModel.capabilities.numberPad ? 1 : 0.5)

            if !viewModel.capabilities.numberPad {
                Text(viewModel.capabilityMessage(for: .numberPad))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                softButton("Menu", style: .light) { viewModel.sendKey(.KEY_MENU) }
                softButton("Guide", style: .light) { viewModel.sendKey(.KEY_GUIDE) }
            }
            HStack(spacing: 8) {
                softButton("Tools", style: .light) { viewModel.sendKey(.KEY_TOOLS) }
                softButton("Info", style: .light) { viewModel.sendKey(.KEY_INFO) }
            }

            HStack(spacing: 8) {
                softButton("Hub", style: .light) { viewModel.sendKey(.KEY_SMARTHUB) }
                softButton("HDMI", style: .light) { viewModel.sendKey(.KEY_HDMI) }
            }

            Button("Quick Launch") {
                viewModel.isAppSheetPresented = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.capabilities.appLaunch)

            if !viewModel.capabilities.appLaunch {
                Text(viewModel.capabilityMessage(for: .appLaunch))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Wake TV") {
                viewModel.wakeTV()
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.capabilities.wakeOnLan)

            if !viewModel.capabilities.wakeOnLan {
                Text(viewModel.capabilityMessage(for: .wakeOnLan))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

#if DEBUG
            DisclosureGroup("Diagnostics") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.diagnosticsSummary)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    if let lastErrorSummary = viewModel.lastErrorSummary {
                        Text("Last Error: \(lastErrorSummary)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Last Error: none")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    ForEach(Array(viewModel.diagnosticsEvents.suffix(8).enumerated()), id: \.offset) { _, event in
                        Text(event)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 6)
            }
            .tint(.white)
#endif
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

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func softButton(
        _ title: String,
        style: UIImpactFeedbackGenerator.FeedbackStyle = .light,
        action: @escaping () -> Void
    ) -> some View {
        Button(title) {
            haptic(style)
            action()
        }
        .buttonStyle(.bordered)
    }

    private var pinSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Enter TV PIN")
                        .font(.title3.weight(.semibold))
                    Text("Type the PIN shown on your Samsung TV.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if viewModel.isProbingVariants {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Detecting protocol variant…")
                            .font(.subheadline)
                    }
                }

                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { index in
                        let char = pinCharacter(at: index)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isPinInputActive ? Color.blue.opacity(0.65) : Color.gray.opacity(0.35), lineWidth: 1)
                            )
                            .frame(width: 52, height: 58)
                            .overlay(
                                Text(char)
                                    .font(.title3.weight(.semibold))
                            )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { isPinInputActive = true }

                if !viewModel.isSubmittingPin {
                    HiddenPINInput(
                        text: pinBinding,
                        isFirstResponder: $isPinInputActive
                    )
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                }

                HStack {
                    Text("Time remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.pinCountdown)s")
                        .font(.caption.weight(.semibold))
                }

                if let pinErrorMessage = viewModel.pinErrorMessage, !pinErrorMessage.isEmpty {
                    Text(pinErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.isSubmittingPin {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Submitting PIN…")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 10) {
                        Button("Confirm PIN") {
                            isPinInputActive = false
                            viewModel.submitPin()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(viewModel.pinCode.count < 4 || viewModel.isProbingVariants)

                        Button("Cancel Pairing", role: .destructive) {
                            isPinInputActive = false
                            viewModel.cancelPinEntry()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }

                Text("Make sure the TV is turned on while pairing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("PIN Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    await MainActor.run {
                        if viewModel.showPinSheet && !viewModel.isSubmittingPin {
                            isPinInputActive = true
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var inlineErrorBanner: some View {
        if case .error = viewModel.connectionState, !viewModel.errorMessage.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
                Text(viewModel.errorMessage)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()
                Button("Retry") {
                    viewModel.connect()
                }
                .font(.caption.bold())
            }
            .padding(12)
            .background(Color.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, horizontalSizeClass == .regular ? 0 : 14)
        }
    }

    private var shouldBlurRemote: Bool {
        if viewModel.showPinSheet { return false }
        switch viewModel.connectionState {
        case .connected:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private var connectionOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "tv.badge.wifi")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text(viewModel.connectionLabel)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(viewModel.connectionGuidance)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                Button("Retry Connection") {
                    viewModel.connect()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 22)
            Spacer()
        }
    }

    private var pinBinding: Binding<String> {
        Binding(
            get: { viewModel.pinCode },
            set: { newValue in
                let digitsOnly = newValue.filter(\.isNumber)
                viewModel.pinCode = String(digitsOnly.prefix(4))
            }
        )
    }

    private func pinCharacter(at index: Int) -> String {
        guard index < viewModel.pinCode.count else { return " " }
        let position = viewModel.pinCode.index(viewModel.pinCode.startIndex, offsetBy: index)
        return String(viewModel.pinCode[position])
    }
}

private struct HiddenPINInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFirstResponder: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField(frame: .zero)
        field.keyboardType = .numberPad
        field.textContentType = .oneTimeCode
        field.tintColor = .clear
        field.textColor = .clear
        field.backgroundColor = .clear
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if isFirstResponder, uiView.window != nil, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFirstResponder, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject {
        @Binding private var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        @objc func editingChanged(_ sender: UITextField) {
            let digitsOnly = (sender.text ?? "").filter(\.isNumber)
            let trimmed = String(digitsOnly.prefix(4))
            if sender.text != trimmed {
                sender.text = trimmed
            }
            text = trimmed
        }
    }
}

#Preview {
    RemoteView(viewModel: RemoteViewModel(
        tv: SamsungTV(name: "Living Room TV", ipAddress: "192.168.1.12", macAddress: "AA:BB:CC:DD:EE:FF", model: "QLED", type: .tizen, protocolType: .modern),
        dependencies: AppDependencies()
    ))
}
