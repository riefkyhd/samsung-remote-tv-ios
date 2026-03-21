import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("TVCapabilities")
struct TVCapabilitiesTests {
    @Test("Modern TV enables wake, app launch, and trackpad")
    func modernCapabilities() {
        let tv = SamsungTV(
            name: "Modern",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:FF",
            model: "QN90",
            type: .tizen
        )
        let caps = tv.capabilities

        #expect(caps.wakeOnLan)
        #expect(caps.appLaunch)
        #expect(caps.trackpad)
        #expect(caps.numberPad)
        #expect(caps.mediaTransport)
        #expect(!caps.encryptedPairing)
    }

    @Test("Encrypted TV disables wake, app launch, and trackpad")
    func encryptedCapabilities() {
        let tv = SamsungTV(
            name: "Encrypted",
            ipAddress: "192.168.1.20",
            macAddress: "AA:BB:CC:DD:EE:FF",
            model: "JU6700",
            type: .encrypted
        )
        let caps = tv.capabilities

        #expect(!caps.wakeOnLan)
        #expect(!caps.appLaunch)
        #expect(!caps.trackpad)
        #expect(caps.encryptedPairing)
        #expect(caps.numberPad)
        #expect(caps.mediaTransport)
    }

    @Test("Empty legacy model resolves as unknown generation conservatively")
    func unknownGenerationFallback() {
        let tv = SamsungTV(
            name: "Unknown",
            ipAddress: "192.168.1.30",
            macAddress: "",
            model: "",
            type: .legacy
        )

        #expect(TVCapabilities.resolveGeneration(for: tv) == .unknown)
        #expect(!tv.capabilities.wakeOnLan)
        #expect(!tv.capabilities.appLaunch)
        #expect(!tv.capabilities.trackpad)
    }
}
