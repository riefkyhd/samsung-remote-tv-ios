import Foundation

struct ForgetPairingUseCase: Sendable {
    private let repository: any TVRepository

    init(repository: any TVRepository) {
        self.repository = repository
    }

    func execute(_ tv: SamsungTV) async throws {
        try await repository.forgetPairing(for: tv)
    }
}
