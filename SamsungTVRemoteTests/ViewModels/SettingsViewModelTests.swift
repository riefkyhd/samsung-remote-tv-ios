import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("SettingsViewModel")
@MainActor
struct SettingsViewModelTests {
    @Test("load reads saved TVs and remote name from use cases")
    func loadReadsUseCases() {
        let repo = MockTVRepository()
        repo.savedTVs = [
            SamsungTV(name: "Living Room", ipAddress: "192.168.1.21", macAddress: "AA", model: "Q", type: .tizen)
        ]
        repo.remoteNameValue = "HomeRemote"
        let sut = makeViewModel(repository: repo)

        sut.load()

        #expect(sut.savedTVs.count == 1)
        #expect(sut.remoteName == "HomeRemote")
    }

    @Test("forgetDevice uses forget use case and removes tv")
    func forgetDeviceUsesUseCase() {
        let repo = MockTVRepository()
        let tv = SamsungTV(name: "Bedroom", ipAddress: "192.168.1.22", macAddress: "AA:BB", model: "Q", type: .tizen)
        repo.savedTVs = [tv]
        let sut = makeViewModel(repository: repo)

        sut.forgetDevice(tv)

        #expect(repo.savedTVs.isEmpty)
        #expect(repo.forgottenTokens.contains("AA:BB"))
    }

    @Test("saveRemoteName writes through use case")
    func saveRemoteNameUsesUseCase() {
        let repo = MockTVRepository()
        let sut = makeViewModel(repository: repo)
        sut.remoteName = "BedroomRemote"

        sut.saveRemoteName()

        #expect(repo.remoteNameValue == "BedroomRemote")
    }

    private func makeViewModel(repository: MockTVRepository) -> SettingsViewModel {
        SettingsViewModel(
            getSavedTVsUseCase: GetSavedTVsUseCase(repository: repository),
            forgetDeviceUseCase: ForgetDeviceUseCase(repository: repository),
            getRemoteNameUseCase: GetRemoteNameUseCase(repository: repository),
            setRemoteNameUseCase: SetRemoteNameUseCase(repository: repository)
        )
    }
}
