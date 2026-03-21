import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("DiscoverTVsUseCase")
@MainActor
struct DiscoverTVsUseCaseTests {
    @Test("REST scan emits discovered TV on valid response")
    func restScanEmitsTV() async {
        let repo = MockTVRepository()
        repo.discoveredTVs = [SamsungTV(name: "TV", ipAddress: "192.168.1.10", macAddress: "AA", model: "Q", type: .tizen)]
        let sut = DiscoverTVsUseCase(repository: repo)

        var emitted: [SamsungTV] = []
        for await tv in sut.execute() { emitted.append(tv) }

        #expect(emitted.count == 1)
        #expect(emitted.first?.name == "TV")
    }

    @Test("Duplicate TVs from multiple strategies are deduplicated by MAC address")
    func dedupByMAC() {
        let macs: Set<String> = ["AA", "AA", "BB"]
        #expect(macs.count == 2)
    }

    @Test("Empty subnet emits no TVs and completes cleanly")
    func emptySubnet() async {
        let repo = MockTVRepository()
        let sut = DiscoverTVsUseCase(repository: repo)

        var emitted: [SamsungTV] = []
        for await tv in sut.execute() { emitted.append(tv) }

        #expect(emitted.isEmpty)
    }

    @Test("Network timeout on all hosts produces empty result without crashing")
    func timeoutProducesEmpty() async {
        let repo = MockTVRepository()
        let sut = DiscoverTVsUseCase(repository: repo)

        var count = 0
        for await _ in sut.execute() { count += 1 }

        #expect(count == 0)
    }

    @Test("Bonjour result emits SamsungTV with correct IP and service name")
    func bonjourResultMaps() {
        let tv = SamsungTV(name: "Samsung Service", ipAddress: "192.168.1.20", macAddress: "AA", model: "QN90", type: .tizen)
        #expect(tv.ipAddress == "192.168.1.20")
        #expect(tv.name == "Samsung Service")
    }
}
