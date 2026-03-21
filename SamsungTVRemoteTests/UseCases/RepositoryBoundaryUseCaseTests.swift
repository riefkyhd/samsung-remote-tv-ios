import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("Repository Boundary Use Cases")
@MainActor
struct RepositoryBoundaryUseCaseTests {
    @Test("DisconnectTVUseCase calls repository disconnect")
    func disconnectUseCaseCallsRepository() async {
        let repo = MockTVRepository()
        let sut = DisconnectTVUseCase(repository: repo)

        await sut.execute()

        #expect(repo.disconnectCalled)
    }

    @Test("LaunchTVAppUseCase forwards app id")
    func launchUseCaseForwardsAppId() async throws {
        let repo = MockTVRepository()
        let sut = LaunchTVAppUseCase(repository: repo)

        try await sut.execute(appId: "111299001912")

        #expect(repo.launchedAppId == "111299001912")
    }

    @Test("GetQuickLaunchAppsUseCase returns curated shortcuts from repository")
    func getQuickLaunchAppsUseCaseReturnsRepositoryList() async throws {
        let repo = MockTVRepository()
        repo.quickLaunchApps = [
            TVApp(id: "11101200001", name: "Netflix", iconURL: nil),
            TVApp(id: "3201512006963", name: "YouTube", iconURL: nil)
        ]
        let sut = GetQuickLaunchAppsUseCase(repository: repo)
        let tv = SamsungTV(
            name: "TV",
            ipAddress: "192.168.1.20",
            macAddress: "AA:BB:CC:DD:EE:FF",
            model: "Q",
            type: .tizen
        )

        let apps = try await sut.execute(for: tv)

        #expect(apps == repo.quickLaunchApps)
    }

    @Test("ForgetPairingUseCase clears pairing state without removing saved tv")
    func forgetPairingUseCaseKeepsSavedTv() async throws {
        let repo = MockTVRepository()
        let tv = SamsungTV(name: "TV", ipAddress: "192.168.1.20", macAddress: "AA:BB:CC:DD:EE:FF", model: "Q", type: .tizen)
        repo.savedTVs = [tv]
        let sut = ForgetPairingUseCase(repository: repo)

        try await sut.execute(tv)

        #expect(repo.pairingForgottenForTVs.count == 1)
        #expect(repo.savedTVs.count == 1)
    }

    @Test("RemoveDeviceUseCase removes saved tv and pairing state")
    func removeDeviceUseCaseRemovesSavedTv() async throws {
        let repo = MockTVRepository()
        let tv = SamsungTV(name: "TV", ipAddress: "192.168.1.20", macAddress: "AA:BB:CC:DD:EE:FF", model: "Q", type: .tizen)
        repo.savedTVs = [tv]
        let sut = RemoveDeviceUseCase(repository: repo)

        try await sut.execute(tv)

        #expect(repo.removedTVs.count == 1)
        #expect(repo.savedTVs.isEmpty)
    }

    @Test("GetRemoteNameUseCase returns stored name")
    func getRemoteNameUseCaseReadsValue() {
        let repo = MockTVRepository()
        repo.remoteNameValue = "LivingRoomRemote"
        let sut = GetRemoteNameUseCase(repository: repo)

        #expect(sut.execute() == "LivingRoomRemote")
    }

    @Test("SetRemoteNameUseCase writes value")
    func setRemoteNameUseCaseWritesValue() throws {
        let repo = MockTVRepository()
        let sut = SetRemoteNameUseCase(repository: repo)

        try sut.execute("BedroomRemote")

        #expect(repo.remoteNameValue == "BedroomRemote")
    }
}
