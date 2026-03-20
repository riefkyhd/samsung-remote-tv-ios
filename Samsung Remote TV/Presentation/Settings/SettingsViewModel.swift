import Foundation
import Observation

@Observable
@MainActor
final class SettingsViewModel {
    var savedTVs: [SamsungTV] = []
    var remoteName = "SamsungTVRemote"
    var alertMessage: String?

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
    }

    func rename(tv: SamsungTV, to newName: String) {
        do {
            try getSavedTVsUseCase.rename(id: tv.id, name: newName)
            load()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func delete(tv: SamsungTV) {
        do {
            try getSavedTVsUseCase.delete(tv)
            load()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func forgetPairing(_ tv: SamsungTV) {
        Task {
            do {
                try await forgetPairingUseCase.execute(tv)
                load()
                print("[TVDBG][Settings] forgot pairing for=\(tv.name)")
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func removeDevice(_ tv: SamsungTV) {
        Task {
            do {
                try await removeDeviceUseCase.execute(tv)
                load()
                print("[TVDBG][Settings] removed device=\(tv.name)")
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func saveRemoteName() {
        do {
            try setRemoteNameUseCase.execute(remoteName)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
