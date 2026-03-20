import Foundation
import Observation

@Observable
@MainActor
final class SettingsViewModel {
    var savedTVs: [SamsungTV] = []
    var remoteName = "SamsungTVRemote"
    var alertMessage: String?

    private let getSavedTVsUseCase: GetSavedTVsUseCase
    private let repository: TVRepositoryImpl

    init(dependencies: AppDependencies) {
        self.getSavedTVsUseCase = dependencies.getSavedTVsUseCase
        self.repository = dependencies.repository
    }

    func load() {
        savedTVs = (try? getSavedTVsUseCase.execute()) ?? []
        remoteName = repository.getRemoteName()
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

    func forgetToken(for tv: SamsungTV) {
        do {
            try repository.forgetToken(for: tv.macAddress)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func saveRemoteName() {
        do {
            try repository.setRemoteName(remoteName)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
