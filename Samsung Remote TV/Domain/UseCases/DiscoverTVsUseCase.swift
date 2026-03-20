import Foundation

struct DiscoverTVsUseCase: Sendable {
    private let repository: any TVRepository

    init(repository: any TVRepository) {
        self.repository = repository
    }

    func execute() -> AsyncStream<SamsungTV> {
        repository.discoverTVs()
    }

    func scanManually(ipAddress: String) async throws -> SamsungTV {
        try await repository.scanTV(at: ipAddress)
    }
}
