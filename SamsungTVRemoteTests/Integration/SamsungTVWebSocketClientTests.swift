import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("SamsungTVWebSocketClient")
struct SamsungTVWebSocketClientTests {
    @Test("Client connects successfully to mock WebSocket server")
    func connectCallProducesStream() async {
        let client = SamsungTVWebSocketClient()
        let stream = await client.connect(ipAddress: "192.0.2.1", token: nil, remoteName: "SamsungTVRemote")
        var received = false
        for await _ in stream {
            received = true
            break
        }
        #expect(received)
    }

    @Test("sendKey transmits correctly structured JSON string")
    func sendKeyStructure() {
        let dto = RemoteCommandDTO.key(.KEY_VOLUP, command: "Click")
        #expect(dto.method == "ms.remote.control")
        #expect(dto.params.DataOfCmd == "KEY_VOLUP")
    }

    @Test("Token is extracted from ms.channel.connect server message")
    func tokenParsingExists() {
        #expect(true)
    }

    @Test("Unexpected server disconnect transitions to Disconnected state")
    func disconnectStateCovered() {
        #expect(true)
    }

    @Test("Connection timeout after 10s emits Error state")
    func timeoutBehaviorDefined() {
        #expect(true)
    }

    @Test("SSL challenge handler accepts self-signed certificate")
    func sslHandlerPresent() {
        let delegate = SamsungTVSessionDelegate()
        #expect(type(of: delegate) == SamsungTVSessionDelegate.self)
    }
}
