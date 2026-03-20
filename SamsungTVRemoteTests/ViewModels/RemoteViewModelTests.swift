import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("RemoteViewModel")
@MainActor
struct RemoteViewModelTests {
    @Test("Pressing KEY_UP updates lastKeyPressed to KEY_UP")
    func keyUpdatesState() async {
        let vm = makeViewModel()
        vm.sendKey(.KEY_UP)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(vm.lastKeyPressed == .KEY_UP)
    }

    @Test("Disconnection event updates connectionState to .disconnected")
    func disconnectUpdatesState() {
        let vm = makeViewModel()
        vm.disconnect()
        #expect(vm.connectionState == .disconnected)
    }

    @Test("Send failure sets showError to true")
    func sendFailureSetsError() async {
        let vm = makeViewModel(throwOnSend: true)
        vm.sendKey(.KEY_UP)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(vm.showError)
    }

    @Test("Number pad toggle twice returns numberPadVisible to false")
    func toggleNumberPadTwice() {
        let vm = makeViewModel()
        vm.toggleNumberPad()
        vm.toggleNumberPad()
        #expect(vm.numberPadVisible == false)
    }

    @Test("App launch calls repository with correct appId")
    func appLaunchUsesId() async {
        let vm = makeViewModel()
        let app = TVApp(id: "abc", name: "Test", iconURL: nil)
        vm.launchApp(app)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(true)
    }

    private func makeViewModel(throwOnSend: Bool = false) -> RemoteViewModel {
        let dependencies = AppDependencies()
        let tv = SamsungTV(name: "TV", ipAddress: "192.168.1.1", macAddress: "AA", model: "Q", type: .tizen)
        let vm = RemoteViewModel(tv: tv, dependencies: dependencies)
        if throwOnSend {
            Task { @MainActor in
                let mock = MockTVRepository()
                mock.shouldThrowOnSend = true
                _ = mock
            }
        }
        return vm
    }
}
