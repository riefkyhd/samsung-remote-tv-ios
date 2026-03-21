import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("WakeOnLanUseCase")
@MainActor
struct WakeOnLanUseCaseTests {
    @Test("Valid MAC address produces 102-byte magic packet")
    func packetLength() throws {
        let sut = WakeOnLanUseCase(repository: MockTVRepository())
        let packet = try sut.makeMagicPacket(for: "AA:BB:CC:DD:EE:FF")
        #expect(packet.count == 102)
    }

    @Test("Magic packet starts with 6 bytes of 0xFF")
    func headerFF() throws {
        let sut = WakeOnLanUseCase(repository: MockTVRepository())
        let packet = try sut.makeMagicPacket(for: "AA:BB:CC:DD:EE:FF")
        #expect(packet.prefix(6).allSatisfy { $0 == 0xFF })
    }

    @Test("Magic packet contains MAC repeated exactly 16 times")
    func repeatedMAC() throws {
        let sut = WakeOnLanUseCase(repository: MockTVRepository())
        let packet = try sut.makeMagicPacket(for: "AA:BB:CC:DD:EE:FF")
        #expect(packet.dropFirst(6).count == 96)
    }

    @Test("Invalid MAC format AA:BB:CC throws TVError.invalidMacAddress")
    func invalidMacThrows() async {
        let sut = WakeOnLanUseCase(repository: MockTVRepository())

        await #expect(throws: TVError.self) {
            _ = try sut.makeMagicPacket(for: "AA:BB:CC")
        }
    }
}
