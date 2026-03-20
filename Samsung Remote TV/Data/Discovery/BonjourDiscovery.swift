import Foundation
import Network

private actor BonjourContinuationResumer {
    private var resumed = false
    private let continuation: CheckedContinuation<SamsungTV?, Never>

    init(continuation: CheckedContinuation<SamsungTV?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: SamsungTV?) {
        guard !resumed else { return }
        resumed = true
        continuation.resume(returning: value)
    }
}

struct BonjourDiscovery: Sendable {
    private let restClient: SamsungTVRestClient

    init(restClient: SamsungTVRestClient) {
        self.restClient = restClient
    }

    func discover() -> AsyncStream<SamsungTV> {
        let samsungCtl = browse(type: "_samsungctl._tcp")
        let multiscreen = browse(type: "_samsung-multiscreen._tcp")
        return .merge(samsungCtl, multiscreen)
    }

    private func browse(type: String) -> AsyncStream<SamsungTV> {
        AsyncStream { continuation in
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
            let queue = DispatchQueue(label: "bonjour-\(type)")

            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    Task { @MainActor in
                        continuation.finish()
                    }
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    Task {
                        if let tv = await resolve(result: result) {
                            continuation.yield(tv)
                        }
                    }
                }
            }

            browser.start(queue: queue)
            continuation.onTermination = { _ in
                browser.cancel()
            }
        }
    }

    private func resolve(result: NWBrowser.Result) async -> SamsungTV? {
        let endpoint = result.endpoint
        guard case .service = endpoint else { return nil }

        return await withCheckedContinuation { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let queue = DispatchQueue(label: "bonjour-resolve")
            let resumer = BonjourContinuationResumer(continuation: continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint else {
                        Task { await resumer.resume(nil) }
                        connection.cancel()
                        return
                    }

                    let ipAddress = host.debugDescription.replacingOccurrences(of: "\"", with: "")
                    guard !NetworkUtils.isLinkLocalIPAddress(ipAddress) else {
                        Task { await resumer.resume(nil) }
                        connection.cancel()
                        return
                    }

                    Task {
                        let tv = try? await restClient.fetchTVInfo(ipAddress: ipAddress)
                        await resumer.resume(tv)
                        connection.cancel()
                    }
                case .failed, .cancelled:
                    Task { await resumer.resume(nil) }
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }
}
