import Foundation

struct GetInstalledAppsUseCase: Sendable {
    private let repository: any TVRepository

    init(repository: any TVRepository) {
        self.repository = repository
    }

    func execute(for tv: SamsungTV) async throws -> [TVApp] {
        try await repository.getInstalledApps(for: tv)
    }
}
