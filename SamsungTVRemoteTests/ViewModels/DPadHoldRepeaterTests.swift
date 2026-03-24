import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("DPadHoldRepeater")
@MainActor
struct DPadHoldRepeaterTests {
    @Test("Single directional tap sends exactly one input")
    func singleTapSendsOneInput() async {
        let repeater = DPadHoldRepeater(
            initialDelay: .milliseconds(80),
            repeatInterval: .milliseconds(30)
        )
        var sent: [RemoteKey] = []

        repeater.press(.KEY_RIGHT) { key, _ in sent.append(key) }
        repeater.release()
        try? await Task.sleep(for: .milliseconds(120))

        #expect(sent == [.KEY_RIGHT])
    }

    @Test("Holding right produces sustained repeated input")
    func holdRightRepeats() async {
        let repeater = DPadHoldRepeater(
            initialDelay: .milliseconds(60),
            repeatInterval: .milliseconds(25)
        )
        var sent: [RemoteKey] = []

        repeater.press(.KEY_RIGHT) { key, _ in sent.append(key) }
        await waitUntil(timeout: .seconds(1)) {
            sent.count >= 2
        }
        repeater.release()

        #expect(sent.count >= 2)
        #expect(sent.allSatisfy { $0 == .KEY_RIGHT })
    }

    @Test("Release stops repeated input immediately")
    func releaseStopsImmediately() async {
        let repeater = DPadHoldRepeater(
            initialDelay: .milliseconds(50),
            repeatInterval: .milliseconds(20)
        )
        var sent: [RemoteKey] = []

        repeater.press(.KEY_RIGHT) { key, _ in sent.append(key) }
        try? await Task.sleep(for: .milliseconds(120))
        repeater.release()
        let countAtRelease = sent.count

        try? await Task.sleep(for: .milliseconds(100))
        #expect(sent.count == countAtRelease)
    }

    @Test("Changing direction cancels old repeat and starts new direction")
    func changeDirectionCancelsOldRepeat() async {
        let repeater = DPadHoldRepeater(
            initialDelay: .milliseconds(50),
            repeatInterval: .milliseconds(20)
        )
        var sent: [RemoteKey] = []

        repeater.press(.KEY_RIGHT) { key, _ in sent.append(key) }
        try? await Task.sleep(for: .milliseconds(90))
        repeater.press(.KEY_LEFT) { key, _ in sent.append(key) }
        try? await Task.sleep(for: .milliseconds(90))
        repeater.release()

        #expect(sent.contains(.KEY_RIGHT))
        #expect(sent.contains(.KEY_LEFT))
        #expect(sent.last == .KEY_LEFT)
        #expect(sent.filter { $0 == .KEY_LEFT }.count >= 2)
    }

    private func waitUntil(timeout: Duration, condition: @escaping () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
