import Foundation
import Observation

@Observable
@MainActor
final class SettingsViewModel {
    var savedTVs: [SamsungTV] = []
    var remoteName = "SamsungTVRemote"
    var alertTitle = L10n.text("common.error", "Error")
    var alertMessage: String?
    private var pairingClearedTVIDs: Set<UUID> = []

    private let getSavedTVsUseCase: GetSavedTVsUseCase
    private let forgetPairingUseCase: ForgetPairingUseCase
    private let removeDeviceUseCase: RemoveDeviceUseCase
    private let getRemoteNameUseCase: GetRemoteNameUseCase
    private let setRemoteNameUseCase: SetRemoteNameUseCase

    init(
        getSavedTVsUseCase: GetSavedTVsUseCase,
        forgetPairingUseCase: ForgetPairingUseCase,
        removeDeviceUseCase: RemoveDeviceUseCase,
        getRemoteNameUseCase: GetRemoteNameUseCase,
        setRemoteNameUseCase: SetRemoteNameUseCase
    ) {
        self.getSavedTVsUseCase = getSavedTVsUseCase
        self.forgetPairingUseCase = forgetPairingUseCase
        self.removeDeviceUseCase = removeDeviceUseCase
        self.getRemoteNameUseCase = getRemoteNameUseCase
        self.setRemoteNameUseCase = setRemoteNameUseCase
    }

    convenience init(dependencies: AppDependencies) {
        self.init(
            getSavedTVsUseCase: dependencies.getSavedTVsUseCase,
            forgetPairingUseCase: dependencies.forgetPairingUseCase,
            removeDeviceUseCase: dependencies.removeDeviceUseCase,
            getRemoteNameUseCase: dependencies.getRemoteNameUseCase,
            setRemoteNameUseCase: dependencies.setRemoteNameUseCase
        )
    }

    func load() {
        savedTVs = (try? getSavedTVsUseCase.execute()) ?? []
        remoteName = getRemoteNameUseCase.execute()
        let visibleIDs = Set(savedTVs.map(\.id))
        pairingClearedTVIDs = pairingClearedTVIDs.intersection(visibleIDs)
    }

    func rename(tv: SamsungTV, to newName: String) {
        do {
            try getSavedTVsUseCase.rename(id: tv.id, name: newName)
            load()
        } catch {
            alertTitle = L10n.text("common.error", "Error")
            alertMessage = error.localizedDescription
        }
    }

    func delete(tv: SamsungTV) {
        do {
            try getSavedTVsUseCase.delete(tv)
            load()
        } catch {
            alertTitle = L10n.text("common.error", "Error")
            alertMessage = error.localizedDescription
        }
    }

    func forgetPairing(_ tv: SamsungTV) {
        Task {
            do {
                try await forgetPairingUseCase.execute(tv)
                load()
                pairingClearedTVIDs.insert(tv.id)
                alertTitle = L10n.text("settings.pairing_reset_title", "Pairing Reset")
                alertMessage = L10n.text("settings.pairing_reset_success", "Pairing data cleared. The next connection will require a new PIN.")
                DiagnosticsLogger.log(
                    .lifecycle,
                    "forget pairing completed",
                    metadata: [
                        "tv": DiagnosticsLogger.redactIdentifier(tv.name)
                    ]
                )
            } catch {
                alertTitle = L10n.text("common.error", "Error")
                alertMessage = error.localizedDescription
            }
        }
    }

    func removeDevice(_ tv: SamsungTV) {
        Task {
            do {
                try await removeDeviceUseCase.execute(tv)
                load()
                pairingClearedTVIDs.remove(tv.id)
                alertTitle = L10n.text("settings.device_removed_title", "Device Removed")
                alertMessage = L10n.text("settings.device_removed_success", "Saved TV and pairing data were removed.")
                DiagnosticsLogger.log(
                    .lifecycle,
                    "remove device completed",
                    metadata: [
                        "tv": DiagnosticsLogger.redactIdentifier(tv.name)
                    ]
                )
            } catch {
                alertTitle = L10n.text("common.error", "Error")
                alertMessage = error.localizedDescription
            }
        }
    }

    func saveRemoteName() {
        do {
            try setRemoteNameUseCase.execute(remoteName)
        } catch {
            alertTitle = L10n.text("common.error", "Error")
            alertMessage = error.localizedDescription
        }
    }

    func isPairingCleared(for tv: SamsungTV) -> Bool {
        pairingClearedTVIDs.contains(tv.id)
    }

    func forgetPairingButtonTitle(for tv: SamsungTV) -> String {
        if isPairingCleared(for: tv) {
            return L10n.text("settings.pairing_cleared", "Pairing Cleared")
        }
        return L10n.text("settings.forget_pairing", "Forget Pairing")
    }
}
