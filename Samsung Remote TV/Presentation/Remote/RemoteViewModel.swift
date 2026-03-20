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
    var installedApps: [TVApp] = []
    var isAppSheetPresented = false
    var isPlaying = false
    var hasConfirmedControl = false
    var showPinSheet = false
    var pinCode = ""
    var pinCountdown = 30
    var isSubmittingPin = false
    var isProbingVariants = false

    private let connectToTVUseCase: ConnectToTVUseCase
    private let sendRemoteKeyUseCase: SendRemoteKeyUseCase
    private let getInstalledAppsUseCase: GetInstalledAppsUseCase
    private let wakeOnLanUseCase: WakeOnLanUseCase
    private let pairWithEncryptedTVUseCase: PairWithEncryptedTVUseCase
    private let repository: TVRepositoryImpl
    private var connectionTask: Task<Void, Never>?
    private var pinTimerTask: Task<Void, Never>?

    init(tv: SamsungTV, dependencies: AppDependencies) {
        self.tv = tv
        self.connectToTVUseCase = dependencies.connectToTVUseCase
        self.sendRemoteKeyUseCase = dependencies.sendRemoteKeyUseCase
        self.getInstalledAppsUseCase = dependencies.getInstalledAppsUseCase
        self.wakeOnLanUseCase = dependencies.wakeOnLanUseCase
        self.pairWithEncryptedTVUseCase = dependencies.pairWithEncryptedTVUseCase
        self.repository = dependencies.repository
    }

    func connect() {
        connectionTask?.cancel()
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
                    showPinSheet = true
                    startPinCountdown()
                }
                if case .error(let error) = state {
                    isProbingVariants = false
                    showError = true
                    errorMessage = error.localizedDescription
                    print("[TVDBG][UI][ERROR] \(errorMessage)")
                }
                if case .connected = state {
                    isProbingVariants = false
                }
            }
        }
    }

    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        pinTimerTask?.cancel()
        Task {
            await repository.disconnect()
        }
        connectionState = .disconnected
        hasConfirmedControl = false
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
                errorMessage = error.localizedDescription
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
                errorMessage = error.localizedDescription
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

    func loadApps() {
        Task {
            do {
                installedApps = try await getInstalledAppsUseCase.execute(for: tv)
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
        }
    }

    func launchApp(_ app: TVApp) {
        guard canSendCommands else { return }
        Task {
            do {
                try await repository.launchApp(appId: app.id)
                hasConfirmedControl = true
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
        }
    }

    func wakeTV() {
        Task {
            do {
                if tv.protocolType == .encrypted {
                    throw TVError.unsupportedProtocol("Older encrypted Samsung TVs cannot power on over network.")
                }
                try await wakeOnLanUseCase.execute(macAddress: tv.macAddress)
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
        }
    }

    var connectionColor: Color {
        switch connectionState {
        case .connected:
            return hasConfirmedControl ? .green : .orange
        case .connecting, .pairing, .pinRequired:
            return .orange
        case .disconnected, .error:
            return .red
        }
    }

    var connectionLabel: String {
        switch connectionState {
        case .connected:
            return hasConfirmedControl ? "Ready" : "Connected"
        case .connecting:
            return "Connecting"
        case .pairing:
            return "Pairing"
        case .pinRequired:
            return "PIN Required"
        case .disconnected:
            return "Offline"
        case .error(let error):
            if case .unsupportedProtocol = error {
                return "Unsupported"
            }
            return "Error"
        }
    }

    var canSendCommands: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    func submitPin() {
        guard !isSubmittingPin else { return }
        let sanitized = pinCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            showError = true
            errorMessage = "Enter PIN shown on TV."
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
                errorMessage = error.localizedDescription
                print("[TVDBG][UI][ERROR] \(errorMessage)")
            }
        }
    }

    func cancelPinEntry() {
        pinTimerTask?.cancel()
        showPinSheet = false
        isProbingVariants = false
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
                disconnect()
            }
        }
    }
}
