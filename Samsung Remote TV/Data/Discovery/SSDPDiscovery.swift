import Foundation
import Network

struct SSDPDiscovery: Sendable {
    private let restClient: SamsungTVRestClient

    init(restClient: SamsungTVRestClient) {
        self.restClient = restClient
    }

    func discover() -> AsyncStream<SamsungTV> {
        AsyncStream { continuation in
            let host = NWEndpoint.Host("239.255.255.250")
            let port = NWEndpoint.Port(rawValue: 1900)!
            let connection = NWConnection(host: host, port: port, using: .udp)
            let queue = DispatchQueue(label: "ssdp-discovery")

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    sendSearch(using: connection)
                    receiveResponses(using: connection, continuation: continuation)
                case .failed, .cancelled:
                    continuation.finish()
                default:
                    break
                }
            }

            connection.start(queue: queue)
            continuation.onTermination = { _ in
                connection.cancel()
            }
        }
    }

    private func sendSearch(using connection: NWConnection) {
        let payload = [
            "M-SEARCH * HTTP/1.1",
            "HOST: 239.255.255.250:1900",
            "MAN: \"ssdp:discover\"",
            "MX: 3",
            "ST: urn:samsung.com:device:RemoteControlReceiver:1",
            "",
            ""
        ].joined(separator: "\r\n")

        connection.send(content: payload.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    private func receiveResponses(
        using connection: NWConnection,
        continuation: AsyncStream<SamsungTV>.Continuation
    ) {
        func loop() {
            connection.receiveMessage { data, _, _, error in
                if error != nil {
                    continuation.finish()
                    return
                }

                if let data,
                   let text = String(data: data, encoding: .utf8),
                   let location = parseLocation(from: text),
                   let url = URL(string: location),
                   let ipAddress = url.host {
                    Task {
                        if let tv = try? await restClient.fetchTVInfo(ipAddress: ipAddress) {
                            continuation.yield(tv)
                        }
                    }
                }

                loop()
            }
        }

        loop()

        Task {
            try? await Task.sleep(for: .seconds(4))
            connection.cancel()
            continuation.finish()
        }
    }

    private func parseLocation(from response: String) -> String? {
        response
            .split(whereSeparator: \.isNewline)
            .first(where: { $0.lowercased().hasPrefix("location:") })?
            .split(separator: ":", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
