import Foundation

struct PairWithEncryptedTVUseCase: Sendable {
    private let repository: any TVRepository

    init(repository: any TVRepository) {
        self.repository = repository
    }

    func complete(pin: String, for tv: SamsungTV) async throws {
        try await repository.completeEncryptedPairing(pin: pin, for: tv)
    }
}
