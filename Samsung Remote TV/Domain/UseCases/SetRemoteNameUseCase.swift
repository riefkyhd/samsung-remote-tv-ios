import Foundation

struct SetRemoteNameUseCase: Sendable {
    private let repository: any TVRepository

    init(repository: any TVRepository) {
        self.repository = repository
    }

    func execute(_ name: String) throws {
        try repository.setRemoteName(name)
    }
}
