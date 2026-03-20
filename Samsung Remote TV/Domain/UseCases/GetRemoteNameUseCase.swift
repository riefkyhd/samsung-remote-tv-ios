import Foundation

struct GetRemoteNameUseCase: Sendable {
    private let repository: any TVRepository

    init(repository: any TVRepository) {
        self.repository = repository
    }

    func execute() -> String {
        repository.getRemoteName()
    }
}
