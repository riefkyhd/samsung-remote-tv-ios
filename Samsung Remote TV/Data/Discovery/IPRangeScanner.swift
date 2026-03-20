import Foundation
import Network

struct IPRangeScanner: Sendable {
    private let restClient: SamsungTVRestClient

    init(restClient: SamsungTVRestClient) {
        self.restClient = restClient
    }

    func discover() -> AsyncStream<SamsungTV> {
        AsyncStream { continuation in
            let task = Task {
                guard let localIP = NetworkUtils.localIPAddress(),
                      !NetworkUtils.isLinkLocalIPAddress(localIP),
                      let prefix = NetworkUtils.subnetPrefix(from: localIP) else {
                    continuation.finish()
                    return
                }

                await withTaskGroup(of: SamsungTV?.self) { group in
                    var nextHost = 1
                    let maxHost = 254
                    let maxConcurrent = 20

                    for _ in 0..<maxConcurrent {
                        guard nextHost <= maxHost else { break }
                        let host = nextHost
                        nextHost += 1
                        group.addTask {
                            guard host != 1, host != 254 else { return nil }
                            let ipAddress = "\(prefix)\(host)"
                            if let tv = try? await restClient.fetchTVInfo(ipAddress: ipAddress) {
                                return tv
                            }
                            let legacyOpen = await isLegacyPortOpen(ipAddress: ipAddress)
                            guard legacyOpen else { return nil }
                            return SamsungTV(
                                name: "Samsung Legacy TV",
                                ipAddress: ipAddress,
                                macAddress: "",
                                model: "Legacy",
                                type: .legacy
                            )
                        }
                    }

                    while let result = await group.next() {
                        if let tv = result {
                            continuation.yield(tv)
                        }

                        guard nextHost <= maxHost else { continue }
                        let host = nextHost
                        nextHost += 1
                        group.addTask {
                            guard host != 1, host != 254 else { return nil }
                            let ipAddress = "\(prefix)\(host)"
                            if let tv = try? await restClient.fetchTVInfo(ipAddress: ipAddress) {
                                return tv
                            }
                            let legacyOpen = await isLegacyPortOpen(ipAddress: ipAddress)
                            guard legacyOpen else { return nil }
                            return SamsungTV(
                                name: "Samsung Legacy TV",
                                ipAddress: ipAddress,
                                macAddress: "",
                                model: "Legacy",
                                type: .legacy
                            )
                        }
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func isLegacyPortOpen(ipAddress: String, timeout: Duration = .milliseconds(450)) async -> Bool {
        let host = NWEndpoint.Host(ipAddress)
        guard let port = NWEndpoint.Port(rawValue: 55000) else { return false }
        let connection = NWConnection(host: host, port: port, using: .tcp)

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    final class ResumeBox: @unchecked Sendable {
                        let lock = NSLock()
                        var resumed = false
                    }
                    let box = ResumeBox()

                    let resume: @Sendable (Bool) -> Void = { value in
                        box.lock.lock()
                        defer { box.lock.unlock() }
                        guard !box.resumed else { return }
                        box.resumed = true
                        continuation.resume(returning: value)
                    }

                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            connection.cancel()
                            resume(true)
                        case .failed, .cancelled:
                            resume(false)
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global())
                }
            }

            group.addTask {
                try? await Task.sleep(for: timeout)
                connection.cancel()
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}
