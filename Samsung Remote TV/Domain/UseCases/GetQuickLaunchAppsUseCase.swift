import Foundation

struct GetQuickLaunchAppsUseCase: Sendable {
    private let repository: any TVRepository

    init(repository: any TVRepository) {
        self.repository = repository
    }

    func execute(for tv: SamsungTV) async throws -> [TVApp] {
        try await repository.getQuickLaunchApps(for: tv)
    }
}
