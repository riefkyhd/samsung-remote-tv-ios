import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class RemoteViewModel {
    let tv: SamsungTV

    var connectionState: TVConnectionState = .disconnected
    var lastKeyPressed: RemoteKey?
    var showError = false
    var errorMessage = ""
    var numberPadVisible = false
    var quickLaunchApps: [TVApp] = []
    var isAppSheetPresented = false
    var isPlaying = false
    var hasConfirmedControl = false
    var showPinSheet = false
    var pinCode = ""
    var pinErrorMessage: String?
    var pinCountdown = 30
    var isSubmittingPin = false
    var isProbingVariants = false
    var capabilities: TVCapabilities { tv.capabilities }
    var connectionAttemptCount = 0
    var diagnosticsEvents: [String] = []
    var lastErrorSummary: String?

    private let connectToTVUseCase: ConnectToTVUseCase
    private let sendRemoteKeyUseCase: SendRemoteKeyUseCase
    private let getQuickLaunchAppsUseCase: GetQuickLaunchAppsUseCase
    private let wakeOnLanUseCase: WakeOnLanUseCase
    private let pairWithEncryptedTVUseCase: PairWithEncryptedTVUseCase
    private let disconnectTVUseCase: DisconnectTVUseCase
    private let launchTVAppUseCase: LaunchTVAppUseCase
    private var connectionTask: Task<Void, Never>?
    private var pinTimerTask: Task<Void, Never>?

    init(
        tv: SamsungTV,
        connectToTVUseCase: ConnectToTVUseCase,
        sendRemoteKeyUseCase: SendRemoteKeyUseCase,
        getQuickLaunchAppsUseCase: GetQuickLaunchAppsUseCase,
        wakeOnLanUseCase: WakeOnLanUseCase,
        pairWithEncryptedTVUseCase: PairWithEncryptedTVUseCase,
        disconnectTVUseCase: DisconnectTVUseCase,
        launchTVAppUseCase: LaunchTVAppUseCase
    ) {
        self.tv = tv
        self.connectToTVUseCase = connectToTVUseCase
        self.sendRemoteKeyUseCase = sendRemoteKeyUseCase
        self.getQuickLaunchAppsUseCase = getQuickLaunchAppsUseCase
        self.wakeOnLanUseCase = wakeOnLanUseCase
        self.pairWithEncryptedTVUseCase = pairWithEncryptedTVUseCase
        self.disconnectTVUseCase = disconnectTVUseCase
        self.launchTVAppUseCase = launchTVAppUseCase
        recordDiagnostics(
            category: .capabilities,
            message: "resolved tv capabilities",
            metadata: [
                "protocol": tv.protocolType.rawValue,
                "generation": TVCapabilities.resolveGeneration(for: tv).rawValue,
                "wakeOnLan": capabilities.wakeOnLan ? "true" : "false",
                "appLaunch": capabilities.appLaunch ? "true" : "false",
                "trackpad": capabilities.trackpad ? "true" : "false",
                "encryptedPairing": capabilities.encryptedPairing ? "true" : "false"
            ]
        )
    }

    convenience init(tv: SamsungTV, dependencies: AppDependencies) {
        self.init(
            tv: tv,
            connectToTVUseCase: dependencies.connectToTVUseCase,
            sendRemoteKeyUseCase: dependencies.sendRemoteKeyUseCase,
            getQuickLaunchAppsUseCase: dependencies.getQuickLaunchAppsUseCase,
            wakeOnLanUseCase: dependencies.wakeOnLanUseCase,
            pairWithEncryptedTVUseCase: dependencies.pairWithEncryptedTVUseCase,
            disconnectTVUseCase: dependencies.disconnectTVUseCase,
            launchTVAppUseCase: dependencies.launchTVAppUseCase
        )
    }

    func connect() {
        connectionTask?.cancel()
        connectionTask = nil
        connectionState = .disconnected
        hasConfirmedControl = false
        connectionAttemptCount = 0
        isProbingVariants = (tv.protocolType == .encrypted)
        recordDiagnostics(
            category: .lifecycle,
            message: "connect requested",
            metadata: [
                "ip": tv.ipAddress,
                "protocol": tv.protocolType.rawValue
            ]
        )
        connectionTask = Task {
            for await state in connectToTVUseCase.executeWithReconnection(tv: tv) {
                connectionState = state
                if case .connecting = state {
                    connectionAttemptCount += 1
                    recordDiagnostics(
                        category: .reconnect,
                        message: "connecting state emitted",
                        metadata: ["attempt": String(connectionAttemptCount)]
                    )
                }
                if case .disconnected = state {
                    hasConfirmedControl = false
                    isProbingVariants = false
                    recordDiagnostics(category: .lifecycle, message: "state=disconnected")
                }
                if case .pairing = state {
                    isProbingVariants = true
                    recordDiagnostics(category: .pairing, message: "state=pairing")
                }
                if case .pinRequired(let countdown) = state {
                    isProbingVariants = false
                    pinCountdown = countdown
                    pinCode = ""
                    pinErrorMessage = nil
                    showPinSheet = true
                    recordDiagnostics(
                        category: .pairing,
                        message: "pin required",
                        metadata: ["countdown": String(countdown)]
                    )
                    startPinCountdown()
                }
                if case .error(let error) = state {
                    isProbingVariants = false
                    hasConfirmedControl = false
                    showError = true
                    errorMessage = userFriendlyMessage(for: error)
                    recordError(context: "connect_stream", error: errorMessage)
                }
                if case .connected = state {
                    isProbingVariants = false
                    // Keep this false until the first successful command/app action confirms control path.
                    hasConfirmedControl = false
                    recordDiagnostics(category: .lifecycle, message: "state=connected")
                }
            }
        }
    }

    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        pinTimerTask?.cancel()
        Task {
            await disconnectTVUseCase.execute()
        }
        connectionState = .disconnected
        hasConfirmedControl = false
        connectionAttemptCount = 0
        recordDiagnostics(category: .lifecycle, message: "disconnect requested")
    }

    func handleRemoteDisappear(shouldDisconnect: Bool) {
        guard shouldDisconnect else { return }
        disconnect()
    }

    func sendKey(_ key: RemoteKey) {
        guard canSendCommands else { return }
        Task {
            do {
                try await sendRemoteKeyUseCase.execute(key)
                lastKeyPressed = key
                hasConfirmedControl = true
            } catch {
                showError = true
                if let tvError = error as? TVError {
                    errorMessage = userFriendlyMessage(for: tvError)
                } else {
                    errorMessage = L10n.text("remote.error_connect_default", "Could not connect. Please make sure the TV is on.")
                }
                recordError(context: "send_key", error: errorMessage)
            }
        }
    }

    func sendLongPressPower() {
        guard canSendCommands else { return }
        Task {
            do {
                try await sendRemoteKeyUseCase.longPress(.KEY_POWEROFF)
                lastKeyPressed = .KEY_POWEROFF
                hasConfirmedControl = true
            } catch {
                showError = true
                if let tvError = error as? TVError {
                    errorMessage = userFriendlyMessage(for: tvError)
                } else {
                    errorMessage = L10n.text("remote.error_connect_default", "Could not connect. Please make sure the TV is on.")
                }
                recordError(context: "long_press_power", error: errorMessage)
            }
        }
    }

    func togglePlayPause() {
        isPlaying.toggle()
        sendKey(isPlaying ? .KEY_PLAY : .KEY_PAUSE)
    }

    func toggleNumberPad() {
        numberPadVisible.toggle()
    }

    func loadQuickLaunchApps() {
        guard capabilities.appLaunch else {
            quickLaunchApps = []
            return
        }
        Task {
            do {
                quickLaunchApps = try await getQuickLaunchAppsUseCase.execute(for: tv)
            } catch {
                showError = true
                if let tvError = error as? TVError {
                    errorMessage = userFriendlyMessage(for: tvError)
                } else {
                    errorMessage = L10n.text("remote.error_connect_default", "Could not connect. Please make sure the TV is on.")
                }
                recordError(context: "load_quick_launch", error: errorMessage)
            }
        }
    }

    func launchApp(_ app: TVApp) {
        guard capabilities.appLaunch else {
            showError = true
            errorMessage = capabilityMessage(for: .appLaunch)
            recordError(context: "launch_app_capability_block", error: errorMessage)
            return
        }
        guard canSendCommands else { return }
        Task {
            do {
                try await launchTVAppUseCase.execute(appId: app.id)
                hasConfirmedControl = true
            } catch {
                showError = true
                if let tvError = error as? TVError {
                    errorMessage = userFriendlyMessage(for: tvError)
                } else {
                    errorMessage = L10n.text("remote.error_connect_default", "Could not connect. Please make sure the TV is on.")
                }
                recordError(context: "launch_app", error: errorMessage)
            }
        }
    }

    func wakeTV() {
        guard capabilities.wakeOnLan else {
            showError = true
            errorMessage = capabilityMessage(for: .wakeOnLan)
            recordError(context: "wake_capability_block", error: errorMessage)
            return
        }
        Task {
            do {
                try await wakeOnLanUseCase.execute(macAddress: tv.macAddress)
            } catch {
                showError = true
                if let tvError = error as? TVError {
                    errorMessage = userFriendlyMessage(for: tvError)
                } else {
                    errorMessage = L10n.text("remote.error_connect_default", "Could not connect. Please make sure the TV is on.")
                }
                recordError(context: "wake_tv", error: errorMessage)
            }
        }
    }

    var connectionColor: Color {
        switch connectionState {
        case .connected:
            return .green
        case .connecting, .pairing:
            return .yellow
        case .pinRequired:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }

    var connectionLabel: String {
        switch connectionState {
        case .connected:
            return hasConfirmedControl ? L10n.text("remote.connection_ready", "Ready") : L10n.text("remote.connection_connected", "Connected")
        case .connecting:
            return connectionAttemptCount > 1 ? L10n.text("remote.connection_reconnecting", "Reconnecting...") : L10n.text("remote.connection_connecting", "Connecting...")
        case .pairing:
            return L10n.text("remote.connection_pairing", "Discovering Pairing...")
        case .pinRequired:
            return L10n.text("remote.connection_enter_pin", "Enter TV PIN")
        case .disconnected:
            return L10n.text("remote.connection_disconnected", "Disconnected")
        case .error(let error):
            return error.localizedDescription
        }
    }

    var connectionGuidance: String {
        if !errorMessage.isEmpty {
            return errorMessage
        }
        switch connectionState {
        case .connected:
            return hasConfirmedControl
                ? L10n.text("remote.guidance_controls_ready", "Controls are ready. Use the remote below.")
                : L10n.text("remote.guidance_confirm_control", "Connection established. Send a command to confirm control.")
        case .connecting:
            return connectionAttemptCount > 1
                ? L10n.text("remote.guidance_restore_session", "Trying to restore the session. Keep the TV on and on the same Wi-Fi.")
                : L10n.text("remote.guidance_connecting", "Connecting to the TV over your local network.")
        case .pairing:
            return L10n.text("remote.guidance_pairing", "Preparing encrypted pairing with this TV model.")
        case .pinRequired:
            return L10n.text("remote.guidance_pin_required", "Enter the PIN shown on your TV before the timer expires.")
        case .disconnected:
            return L10n.text("remote.guidance_disconnected", "Make sure your TV is on and on the same Wi-Fi.")
        case .error:
            return L10n.text("remote.guidance_error", "Check TV power and Wi-Fi, then retry.")
        }
    }

    var canSendCommands: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    func capabilityMessage(for action: TVCapabilityAction) -> String {
        capabilities.unsupportedReason(for: action) ?? L10n.text("remote.capability_unsupported", "This action is not supported on this TV.")
    }

    func submitPin() {
        guard !isSubmittingPin else { return }
        let sanitized = pinCode.trimmingCharacters(in: .whitespacesAndNewlines)
        pinErrorMessage = nil
        guard !sanitized.isEmpty else {
            showError = true
            errorMessage = L10n.text("remote.pin_error_enter", "Enter PIN shown on TV.")
            pinErrorMessage = errorMessage
            recordError(context: "submit_pin_validation", error: errorMessage)
            return
        }

        Task {
            isSubmittingPin = true
            defer { isSubmittingPin = false }
            do {
                try await pairWithEncryptedTVUseCase.complete(pin: sanitized, for: tv)
                pinTimerTask?.cancel()
                showPinSheet = false
                // Re-establish the live transport stream via repository connect path.
                connectionState = .connecting
                hasConfirmedControl = false
                recordDiagnostics(category: .pairing, message: "pin accepted; reconnecting transport")
                connect()
            } catch {
                showError = true
                if let tvError = error as? TVError {
                    errorMessage = userFriendlyMessage(for: tvError)
                } else {
                    errorMessage = L10n.text("remote.error_connect_default", "Could not connect. Please make sure the TV is on.")
                }
                pinErrorMessage = errorMessage
                recordError(context: "submit_pin", error: errorMessage)
            }
        }
    }

    func cancelPinEntry() {
        pinTimerTask?.cancel()
        showPinSheet = false
        isProbingVariants = false
        pinErrorMessage = nil
        connectionState = .disconnected
        disconnect()
    }

    private func startPinCountdown() {
        pinTimerTask?.cancel()
        pinTimerTask = Task {
            while !Task.isCancelled && pinCountdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                pinCountdown -= 1
            }

            if pinCountdown == 0 {
                showPinSheet = false
                connectionState = .error(.pinTimeout)
                showError = true
                errorMessage = TVError.pinTimeout.localizedDescription
                pinErrorMessage = nil
                recordError(context: "pin_countdown_timeout", error: errorMessage)
                disconnect()
            }
        }
    }

    var diagnosticsSummary: String {
        let generation = TVCapabilities.resolveGeneration(for: tv).rawValue
        return "Protocol: \(tv.protocolType.rawValue) | Generation: \(generation) | Attempts: \(connectionAttemptCount)"
    }

    private func recordDiagnostics(
        category: DiagnosticsCategory,
        message: String,
        metadata: [String: String] = [:]
    ) {
        DiagnosticsLogger.log(category, message, metadata: metadata)
        let event = formatDiagnosticsEvent(category: category, message: message, metadata: metadata)
        diagnosticsEvents.append(event)
        if diagnosticsEvents.count > 20 {
            diagnosticsEvents.removeFirst(diagnosticsEvents.count - 20)
        }
    }

    private func recordError(context: String, error: String) {
        lastErrorSummary = "\(context): \(error)"
        recordDiagnostics(
            category: .error,
            message: "ui error",
            metadata: [
                "context": context,
                "message": error
            ]
        )
    }

    private func formatDiagnosticsEvent(
        category: DiagnosticsCategory,
        message: String,
        metadata: [String: String]
    ) -> String {
        let metadataText = metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        if metadataText.isEmpty {
            return "[\(category.rawValue)] \(message)"
        }
        return "[\(category.rawValue)] \(message) \(metadataText)"
    }

    private func userFriendlyMessage(for error: TVError) -> String {
        switch error {
        case .pairingRejected:
            return L10n.text("remote.error_pairing_rejected", "Incorrect PIN. Check the TV screen and enter the new PIN.")
        case .connectionFailed, .notConnected, .spcHandshakeFailed:
            return L10n.text("remote.error_connection_failed", "Could not connect to TV. Keep TV on the same Wi-Fi, then tap Retry Connection.")
        case .spcTokenExpired:
            return L10n.text("remote.error_token_expired", "Pairing session expired. Open Settings > Forget Pairing, then connect again.")
        case .spcPairingFailed(let reason):
            if reason.lowercased().contains("pin page") {
                return L10n.text("remote.error_pin_page", "Could not open the PIN page on TV. Keep TV awake and try again.")
            }
            return L10n.text("remote.error_pairing_failed", "Could not complete pairing. Retry, or use Forget Pairing in Settings.")
        case .unsupportedProtocol:
            return L10n.text("remote.error_unsupported_protocol", "This TV protocol is not supported for this action.")
        case .appLaunchFailed:
            return L10n.text("remote.error_quick_launch_failed", "Quick Launch failed. Ensure the app is available on your TV and try again.")
        case .invalidResponse:
            return L10n.text("remote.error_invalid_response", "TV replied unexpectedly. Retry the connection.")
        case .notOnWifi:
            return L10n.text("remote.error_not_on_wifi", "Please connect to Wi-Fi to control your TV.")
        case .pinTimeout:
            return L10n.text("remote.error_pin_timeout", "PIN timed out. Request a new PIN and enter it within 30 seconds.")
        default:
            return L10n.text("remote.error_action_failed", "Action failed. Check TV power/Wi-Fi and retry.")
        }
    }
}
