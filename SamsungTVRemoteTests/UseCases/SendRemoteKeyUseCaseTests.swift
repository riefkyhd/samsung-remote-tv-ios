import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("SendRemoteKeyUseCase")
@MainActor
struct SendRemoteKeyUseCaseTests {
    @Test("Connected state sends correctly formatted JSON for KEY_VOLUP")
    func sendsVolUp() async throws {
        let repo = MockTVRepository()
        let sut = SendRemoteKeyUseCase(repository: repo)

        try await sut.execute(.KEY_VOLUP)
        #expect(repo.sentKeys.last?.0 == .KEY_VOLUP)
        #expect(repo.sentKeys.last?.1 == "Click")
    }

    @Test("Disconnected state throws TVError.notConnected")
    func disconnectedThrows() async {
        let repo = MockTVRepository()
        repo.shouldThrowOnSend = true
        let sut = SendRemoteKeyUseCase(repository: repo)

        await #expect(throws: TVError.self) {
            try await sut.execute(.KEY_VOLUP)
        }
    }

    @Test("Long-press sends Press command then Release command in order")
    func longPressOrder() async throws {
        let repo = MockTVRepository()
        let sut = SendRemoteKeyUseCase(repository: repo)

        try await sut.longPress(.KEY_POWER, duration: .milliseconds(1))

        #expect(repo.sentKeys.count == 2)
        #expect(repo.sentKeys[0].1 == "Press")
        #expect(repo.sentKeys[1].1 == "Release")
    }

    @Test("Rapid sends within 100ms are debounced to single command")
    func debounceWorks() async throws {
        let repo = MockTVRepository()
        let debouncer = RemoteKeyDebouncer(minimumInterval: 10)
        let sut = SendRemoteKeyUseCase(repository: repo, debouncer: debouncer)

        try await sut.execute(.KEY_UP)
        try await sut.execute(.KEY_UP)

        #expect(repo.sentKeys.count == 1)
    }
}
