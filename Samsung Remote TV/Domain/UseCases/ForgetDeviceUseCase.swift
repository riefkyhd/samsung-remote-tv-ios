import Foundation

struct ForgetDeviceUseCase: Sendable {
    private let repository: any TVRepository

    init(repository: any TVRepository) {
        self.repository = repository
    }

    func execute(_ tv: SamsungTV) throws {
        let identifier = tv.macAddress.isEmpty ? "ip_\(tv.ipAddress)" : tv.macAddress
        try repository.forgetToken(for: identifier)
        if !tv.macAddress.isEmpty && tv.macAddress != identifier {
            try repository.forgetToken(for: tv.macAddress)
        }
        try repository.deleteTV(tv)
    }
}
