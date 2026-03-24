import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("VolumeHoldRepeater")
@MainActor
struct VolumeHoldRepeaterTests {
    @Test("Single volume tap sends one step")
    func singleTapSendsOneInput() async {
        let repeater = VolumeHoldRepeater(
            initialDelay: .milliseconds(80),
            repeatInterval: .milliseconds(40)
        )
        var sent: [RemoteKey] = []

        repeater.press(.KEY_VOLUP) { key, _ in sent.append(key) }
        repeater.release()
        try? await Task.sleep(for: .milliseconds(120))

        #expect(sent == [.KEY_VOLUP])
    }

    @Test("Holding volume up repeats with controlled cadence")
    func holdVolumeUpRepeats() async {
        let repeater = VolumeHoldRepeater(
            initialDelay: .milliseconds(70),
            repeatInterval: .milliseconds(45)
        )
        var sent: [RemoteKey] = []

        repeater.press(.KEY_VOLUP) { key, _ in sent.append(key) }
        await waitUntil(timeout: .seconds(1)) {
            sent.count >= 2
        }
        repeater.release()

        #expect(sent.count >= 2)
        #expect(sent.allSatisfy { $0 == .KEY_VOLUP })
    }

    @Test("Volume release stops repeats immediately")
    func releaseStopsImmediately() async {
        let repeater = VolumeHoldRepeater(
            initialDelay: .milliseconds(50),
            repeatInterval: .milliseconds(35)
        )
        var sent: [RemoteKey] = []

        repeater.press(.KEY_VOLDOWN) { key, _ in sent.append(key) }
        try? await Task.sleep(for: .milliseconds(130))
        repeater.release()
        let countAtRelease = sent.count

        try? await Task.sleep(for: .milliseconds(120))
        #expect(sent.count == countAtRelease)
    }

    private func waitUntil(timeout: Duration, condition: @escaping () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
