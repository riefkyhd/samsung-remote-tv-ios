import Foundation

struct GetSavedTVsUseCase: Sendable {
    private let repository: any TVRepository

    init(repository: any TVRepository) {
        self.repository = repository
    }

    func execute() throws -> [SamsungTV] {
        try repository.getSavedTVs()
    }

    func save(_ tv: SamsungTV) throws {
        try repository.saveTV(tv)
    }

    func delete(_ tv: SamsungTV) throws {
        try repository.deleteTV(tv)
    }

    func rename(id: UUID, name: String) throws {
        try repository.renameTV(id: id, name: name)
    }
}
