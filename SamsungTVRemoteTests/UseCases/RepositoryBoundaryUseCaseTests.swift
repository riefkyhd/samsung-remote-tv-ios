import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("Repository Boundary Use Cases")
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

    @Test("ForgetDeviceUseCase forgets token and removes saved tv")
    func forgetUseCaseCleansPairingAndSavedTv() throws {
        let repo = MockTVRepository()
        let tv = SamsungTV(name: "TV", ipAddress: "192.168.1.20", macAddress: "AA:BB:CC:DD:EE:FF", model: "Q", type: .tizen)
        repo.savedTVs = [tv]
        let sut = ForgetDeviceUseCase(repository: repo)

        try sut.execute(tv)

        #expect(repo.forgottenTokens.contains("AA:BB:CC:DD:EE:FF"))
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
