import Foundation
import Observation

@Observable
@MainActor
final class SettingsViewModel {
    var savedTVs: [SamsungTV] = []
    var remoteName = "SamsungTVRemote"
    var alertMessage: String?

    private let getSavedTVsUseCase: GetSavedTVsUseCase
    private let forgetDeviceUseCase: ForgetDeviceUseCase
    private let getRemoteNameUseCase: GetRemoteNameUseCase
    private let setRemoteNameUseCase: SetRemoteNameUseCase

    init(
        getSavedTVsUseCase: GetSavedTVsUseCase,
        forgetDeviceUseCase: ForgetDeviceUseCase,
        getRemoteNameUseCase: GetRemoteNameUseCase,
        setRemoteNameUseCase: SetRemoteNameUseCase
    ) {
        self.getSavedTVsUseCase = getSavedTVsUseCase
        self.forgetDeviceUseCase = forgetDeviceUseCase
        self.getRemoteNameUseCase = getRemoteNameUseCase
        self.setRemoteNameUseCase = setRemoteNameUseCase
    }

    convenience init(dependencies: AppDependencies) {
        self.init(
            getSavedTVsUseCase: dependencies.getSavedTVsUseCase,
            forgetDeviceUseCase: dependencies.forgetDeviceUseCase,
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

    func forgetDevice(_ tv: SamsungTV) {
        do {
            try forgetDeviceUseCase.execute(tv)
            load()
            print("[TVDBG][Settings] forgot device name=\(tv.name)")
        } catch {
            alertMessage = error.localizedDescription
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
