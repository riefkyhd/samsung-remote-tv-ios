import Foundation
import Network

enum NetworkUtils {
    nonisolated static func isLinkLocalIPAddress(_ ipAddress: String) -> Bool {
        ipAddress.hasPrefix("169.254.")
    }

    nonisolated static func isUsableLANAddress(_ ipAddress: String) -> Bool {
        guard !isLinkLocalIPAddress(ipAddress) else { return false }
        return ipAddress.hasPrefix("192.168.") || ipAddress.hasPrefix("10.") || ipAddress.hasPrefix("172.")
    }

    nonisolated static func localIPAddress() -> String? {
        var preferredAddress: String?
        var fallbackAddress: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }

        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)

            var hostName = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostName,
                socklen_t(hostName.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if result == 0 {
                let candidate = String(cString: hostName)
                guard !isLinkLocalIPAddress(candidate), !candidate.hasPrefix("127.") else {
                    continue
                }

                if name == "en0" || name.hasPrefix("en") {
                    preferredAddress = candidate
                    break
                }

                if fallbackAddress == nil, isUsableLANAddress(candidate) {
                    fallbackAddress = candidate
                }
            }
        }

        return preferredAddress ?? fallbackAddress
    }

    nonisolated static func subnetPrefix(from ipAddress: String) -> String? {
        let components = ipAddress.split(separator: ".")
        guard components.count == 4 else { return nil }
        return components.prefix(3).joined(separator: ".") + "."
    }

    static func isOnWiFi() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "wifi-monitor")
            monitor.pathUpdateHandler = { path in
                let wifi = path.status == .satisfied && path.usesInterfaceType(.wifi)
                continuation.resume(returning: wifi)
                monitor.cancel()
            }
            monitor.start(queue: queue)
        }
    }

    static func isTCPPortOpen(ipAddress: String, port: UInt16, timeout: Duration = .seconds(2)) async -> Bool {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return false
        }
        let connection = NWConnection(host: NWEndpoint.Host(ipAddress), port: endpointPort, using: .tcp)

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

actor DiscoveredMACActor {
    private var values: Set<String> = []

    func insertIfNeeded(mac: String, ipAddress: String) -> Bool {
        let normalized = mac.isEmpty ? "IP:\(ipAddress)" : mac.uppercased()
        if values.contains(normalized) {
            return false
        }
        values.insert(normalized)
        return true
    }
}

extension AsyncStream where Element: Sendable {
    static func merge(_ streams: AsyncStream<Element>...) -> AsyncStream<Element> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    for stream in streams {
                        group.addTask {
                            for await value in stream {
                                continuation.yield(value)
                            }
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
}
