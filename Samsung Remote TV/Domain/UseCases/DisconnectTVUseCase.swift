import Foundation

struct DisconnectTVUseCase: Sendable {
    private let repository: any TVRepository

    init(repository: any TVRepository) {
        self.repository = repository
    }

    func execute() async {
        await repository.disconnect()
    }
}
