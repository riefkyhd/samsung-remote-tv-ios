import Foundation

struct WakeOnLanUseCase: Sendable {
    private let repository: any TVRepository

    init(repository: any TVRepository) {
        self.repository = repository
    }

    func execute(macAddress: String) async throws {
        try await repository.wakeOnLan(macAddress: macAddress)
    }

    func makeMagicPacket(for macAddress: String) throws -> Data {
        let normalized = macAddress.replacingOccurrences(of: "-", with: ":")
        let regex = /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/
        guard normalized.wholeMatch(of: regex) != nil else {
            throw TVError.invalidMacAddress
        }

        let macBytes = normalized
            .split(separator: ":")
            .compactMap { UInt8($0, radix: 16) }

        guard macBytes.count == 6 else {
            throw TVError.invalidMacAddress
        }

        var payload = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            payload.append(contentsOf: macBytes)
        }
        return payload
    }
}
