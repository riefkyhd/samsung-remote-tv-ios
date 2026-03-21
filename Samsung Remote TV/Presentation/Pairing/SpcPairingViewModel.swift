import Foundation
import Observation

@Observable
@MainActor
final class SpcPairingViewModel {
    var pinCode = ""
    var countdown = 30
    var isSubmitting = false
    var isProbingVariants = false
    var errorMessage: String?

    private let tv: SamsungTV
    private let pairUseCase: PairWithEncryptedTVUseCase
    private var timerTask: Task<Void, Never>?

    init(tv: SamsungTV, pairUseCase: PairWithEncryptedTVUseCase) {
        self.tv = tv
        self.pairUseCase = pairUseCase
    }

    func startCountdown(onTimeout: @escaping @MainActor () -> Void) {
        timerTask?.cancel()
        countdown = 30
        timerTask = Task {
            while !Task.isCancelled && countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                countdown -= 1
            }
            if countdown == 0 {
                onTimeout()
            }
        }
    }

    func cancelCountdown() {
        timerTask?.cancel()
        timerTask = nil
    }

    func submit(onSuccess: @escaping @MainActor () -> Void) async {
        guard pinCode.count >= 4 else {
            errorMessage = "Enter the PIN shown on TV."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await pairUseCase.complete(pin: pinCode, for: tv)
            onSuccess()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
