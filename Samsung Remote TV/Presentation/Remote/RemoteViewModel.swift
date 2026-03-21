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
        isProbingVariants = (tv.protocolType == .encrypted)
        connectionTask = Task {
            for await state in connectToTVUseCase.executeWithReconnection(tv: tv) {
                connectionState = state
                if case .disconnected = state {
                    hasConfirmedControl = false
                    isProbingVariants = false
                }
                if case .pairing = state {
                    isProbingVariants = true
                }
                if case .pinRequired(let countdown) = state {
                    isProbingVariants = false
                    pinCountdown = countdown
                    pinCode = ""
                    pinErrorMessage = nil
                    showPinSheet = true
                    startPinCountdown()
                }
                if case .error(let error) = state {
                    isProbingVariants = false
                    hasConfirmedControl = false
                    showError = true
                    errorMessage = userFriendlyMessage(for: error)
                    print("[TVDBG][UI][ERROR] \(errorMessage)")
                }
                if case .connected = state {
                    isProbingVariants = false
                    hasConfirmedControl = true
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
                    errorMessage = "Could not connect. Please make sure the TV is on."
                }
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
                    errorMessage = "Could not connect. Please make sure the TV is on."
                }
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
                    errorMessage = "Could not connect. Please make sure the TV is on."
                }
            }
        }
    }

    func launchApp(_ app: TVApp) {
        guard capabilities.appLaunch else {
            showError = true
            errorMessage = capabilityMessage(for: .appLaunch)
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
                    errorMessage = "Could not connect. Please make sure the TV is on."
                }
            }
        }
    }

    func wakeTV() {
        guard capabilities.wakeOnLan else {
            showError = true
            errorMessage = capabilityMessage(for: .wakeOnLan)
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
                    errorMessage = "Could not connect. Please make sure the TV is on."
                }
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
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .pairing:
            return "Pairing..."
        case .pinRequired:
            return "Enter PIN"
        case .disconnected:
            return "Disconnected"
        case .error(let error):
            return error.localizedDescription
        }
    }

    var canSendCommands: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    func capabilityMessage(for action: TVCapabilityAction) -> String {
        capabilities.unsupportedReason(for: action) ?? "This action is not supported on this TV."
    }

    func submitPin() {
        guard !isSubmittingPin else { return }
        let sanitized = pinCode.trimmingCharacters(in: .whitespacesAndNewlines)
        pinErrorMessage = nil
        guard !sanitized.isEmpty else {
            showError = true
            errorMessage = "Enter PIN shown on TV."
            pinErrorMessage = errorMessage
            print("[TVDBG][UI][ERROR] \(errorMessage)")
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
                connect()
            } catch {
                showError = true
                if let tvError = error as? TVError {
                    errorMessage = userFriendlyMessage(for: tvError)
                } else {
                    errorMessage = "Could not connect. Please make sure the TV is on."
                }
                pinErrorMessage = errorMessage
                print("[TVDBG][UI][ERROR] \(errorMessage)")
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
                disconnect()
            }
        }
    }

    private func userFriendlyMessage(for error: TVError) -> String {
        switch error {
        case .pairingRejected:
            return "Incorrect PIN. Please try again."
        case .connectionFailed, .notConnected, .spcHandshakeFailed:
            return "Could not connect to TV. Please make sure the TV is on and connected to the same Wi-Fi."
        case .spcTokenExpired:
            return "Pairing expired. Please reconnect to the TV."
        case .spcPairingFailed(let reason):
            if reason.lowercased().contains("pin page") {
                return "Could not open PIN on TV. Please try again."
            }
            return "Could not start pairing. Please try again."
        case .notOnWifi:
            return "Please connect to Wi-Fi to control your TV."
        case .pinTimeout:
            return "PIN entry timed out. Please try again."
        default:
            return "Could not connect. Please make sure the TV is on."
        }
    }
}
