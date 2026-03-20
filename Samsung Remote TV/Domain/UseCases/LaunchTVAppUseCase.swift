import Foundation

struct LaunchTVAppUseCase: Sendable {
    private let repository: any TVRepository

    init(repository: any TVRepository) {
        self.repository = repository
    }

    func execute(appId: String) async throws {
        try await repository.launchApp(appId: appId)
    }
}
