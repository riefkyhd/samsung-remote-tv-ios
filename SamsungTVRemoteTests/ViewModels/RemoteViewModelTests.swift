import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("RemoteViewModel")
@MainActor
struct RemoteViewModelTests {
    @Test("Pressing KEY_UP updates lastKeyPressed to KEY_UP")
    func keyUpdatesState() async {
        let vm = makeViewModel()
        vm.connectionState = .connected

        vm.sendKey(.KEY_UP)
        try? await Task.sleep(for: .milliseconds(30))

        #expect(vm.lastKeyPressed == .KEY_UP)
    }

    @Test("Disconnection event updates connectionState to .disconnected")
    func disconnectUpdatesState() async {
        let vm = makeViewModel()
        vm.connectionState = .connected

        vm.disconnect()
        try? await Task.sleep(for: .milliseconds(30))

        #expect(vm.connectionState == .disconnected)
    }

    @Test("Send failure sets showError to true")
    func sendFailureSetsError() async {
        let vm = makeViewModel(throwOnSend: true)
        vm.connectionState = .connected

        vm.sendKey(.KEY_UP)
        try? await Task.sleep(for: .milliseconds(30))

        #expect(vm.showError)
        #expect(!vm.errorMessage.isEmpty)
    }

    @Test("Number pad toggle twice returns numberPadVisible to false")
    func toggleNumberPadTwice() {
        let vm = makeViewModel()

        vm.toggleNumberPad()
        vm.toggleNumberPad()

        #expect(vm.numberPadVisible == false)
    }

    @Test("App launch uses launch use case")
    func appLaunchUsesUseCase() async {
        let repo = MockTVRepository()
        let vm = makeViewModel(repository: repo)
        vm.connectionState = .connected
        let app = TVApp(id: "abc", name: "Test", iconURL: nil)

        vm.launchApp(app)
        try? await Task.sleep(for: .milliseconds(30))

        #expect(repo.launchedAppId == "abc")
    }

    @Test("Settings presentation path does not disconnect active session")
    func settingsPresentationDoesNotDisconnect() async {
        let repo = MockTVRepository()
        let vm = makeViewModel(repository: repo)
        vm.connectionState = .connected

        vm.handleRemoteDisappear(shouldDisconnect: false)
        try? await Task.sleep(for: .milliseconds(30))

        #expect(repo.disconnectCalled == false)
        #expect(vm.connectionState == .connected)
    }

    @Test("Explicit remote disappear disconnects session")
    func explicitDisappearDisconnects() async {
        let repo = MockTVRepository()
        let vm = makeViewModel(repository: repo)
        vm.connectionState = .connected

        vm.handleRemoteDisappear(shouldDisconnect: true)
        try? await Task.sleep(for: .milliseconds(30))

        #expect(repo.disconnectCalled == true)
        #expect(vm.connectionState == .disconnected)
    }

    private func makeViewModel(
        repository: MockTVRepository = MockTVRepository(),
        throwOnSend: Bool = false
    ) -> RemoteViewModel {
        repository.shouldThrowOnSend = throwOnSend

        let tv = SamsungTV(
            name: "TV",
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF",
            model: "Q",
            type: .tizen
        )

        return RemoteViewModel(
            tv: tv,
            connectToTVUseCase: ConnectToTVUseCase(repository: repository),
            sendRemoteKeyUseCase: SendRemoteKeyUseCase(repository: repository),
            getInstalledAppsUseCase: GetInstalledAppsUseCase(repository: repository),
            wakeOnLanUseCase: WakeOnLanUseCase(repository: repository),
            pairWithEncryptedTVUseCase: PairWithEncryptedTVUseCase(repository: repository),
            disconnectTVUseCase: DisconnectTVUseCase(repository: repository),
            launchTVAppUseCase: LaunchTVAppUseCase(repository: repository)
        )
    }
}
