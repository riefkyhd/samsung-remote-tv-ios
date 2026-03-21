import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("DiscoveryViewModel")
@MainActor
struct DiscoveryViewModelTests {
    @Test("Manual connect rejects empty IP")
    func manualConnectRejectsEmptyIP() async {
        let sut = makeViewModel()
        sut.manualIPAddress = "   "

        let result = await sut.connectManual()

        #expect(result == nil)
        #expect(sut.alertMessage == "Please enter an IP address.")
    }

    @Test("Manual connect rejects invalid IPv4 format")
    func manualConnectRejectsInvalidIPv4() async {
        let sut = makeViewModel()
        sut.manualIPAddress = "192.168.1.999"

        let result = await sut.connectManual()

        #expect(result == nil)
        #expect(sut.alertMessage == "Please enter a valid IPv4 address.")
    }

    @Test("Manual connect returns TV and closes sheet on success")
    func manualConnectReturnsTVOnSuccess() async {
        let repo = MockTVRepository()
        let tv = SamsungTV(
            name: "Living Room TV",
            ipAddress: "192.168.1.20",
            macAddress: "AA:BB:CC:DD:EE:FF",
            model: "Q",
            type: .tizen
        )
        repo.discoveredTVs = [tv]
        let sut = makeViewModel(repository: repo)
        sut.showManualSheet = true
        sut.manualIPAddress = tv.ipAddress

        let result = await sut.connectManual()

        #expect(result?.ipAddress == tv.ipAddress)
        #expect(sut.showManualSheet == false)
        #expect(sut.manualIPAddress.isEmpty)
        #expect(sut.discoveredTVs.first?.ipAddress == tv.ipAddress)
    }

    @Test("Manual connect trims whitespace before scanning")
    func manualConnectTrimsWhitespaceInput() async {
        let repo = MockTVRepository()
        let tv = SamsungTV(
            name: "Bedroom TV",
            ipAddress: "192.168.1.21",
            macAddress: "AA:BB:CC:DD:EE:11",
            model: "Q",
            type: .tizen
        )
        repo.discoveredTVs = [tv]
        let sut = makeViewModel(repository: repo)
        sut.manualIPAddress = "  192.168.1.21  "

        let result = await sut.connectManual()

        #expect(result?.ipAddress == "192.168.1.21")
        #expect(sut.alertMessage == nil)
    }

    @Test("Manual connect updates existing discovered entry instead of duplicating IP")
    func manualConnectUpdatesExistingEntryByIPAddress() async {
        let repo = MockTVRepository()
        let stale = SamsungTV(
            name: "Stale Name",
            ipAddress: "192.168.1.30",
            macAddress: "AA:BB:CC:DD:EE:12",
            model: "Old",
            type: .legacy
        )
        let refreshed = SamsungTV(
            name: "Living Room TV",
            ipAddress: "192.168.1.30",
            macAddress: "AA:BB:CC:DD:EE:12",
            model: "QN90",
            type: .tizen
        )
        repo.discoveredTVs = [refreshed]
        let sut = makeViewModel(repository: repo)
        sut.discoveredTVs = [stale]
        sut.manualIPAddress = "192.168.1.30"

        _ = await sut.connectManual()

        #expect(sut.discoveredTVs.count == 1)
        #expect(sut.discoveredTVs[0].name == "Living Room TV")
        #expect(sut.discoveredTVs[0].model == "QN90")
    }

    @Test("Manual connect shows clear error for unreachable/unsupported host")
    func manualConnectShowsClearErrorForUnreachableHost() async {
        let sut = makeViewModel()
        sut.manualIPAddress = "192.168.1.20"

        let result = await sut.connectManual()

        #expect(result == nil)
        #expect(sut.alertMessage == "Could not reach a compatible Samsung TV at that IP.")
    }

    private func makeViewModel(repository: MockTVRepository = MockTVRepository()) -> DiscoveryViewModel {
        DiscoveryViewModel(
            discoverTVsUseCase: DiscoverTVsUseCase(repository: repository),
            getSavedTVsUseCase: GetSavedTVsUseCase(repository: repository)
        )
    }
}
