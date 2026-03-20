import Foundation
import Combine

#if canImport(SmartView)
import SmartView

final class SmartViewSDKClient: NSObject, ObservableObject {
    @Published var connectionState: TVConnectionState = .disconnected
    @Published var pinRequired = false

    var isSDKAvailable: Bool { true }

    private var service: Service?
    private var channel: Channel?
    private let serviceSearch = Service.search()
    private var discoveryDelegate: DiscoveryDelegate?
    private var servicesByIP: [String: Service] = [:]
    private var continuation: AsyncStream<TVConnectionState>.Continuation?
    private var lastTV: SamsungTV?
    private var lastRemoteName = "SamsungTVRemote"
    private var pendingPin: String?
    private var didSignalConnected = false

    func startDiscovery(onFound: @escaping (SamsungTV) -> Void) {
        let delegate = DiscoveryDelegate(onFound: { [weak self] service in
            guard let self else { return }
            let ip = self.extractHost(from: service.uri)
            guard !ip.isEmpty else { return }
            servicesByIP[ip] = service

            let tv = SamsungTV(
                name: service.name,
                ipAddress: ip,
                macAddress: "ip_\(ip)",
                model: service.name,
                type: .encrypted,
                protocolType: .encrypted
            )
            onFound(tv)
        })

        discoveryDelegate = delegate
        serviceSearch.delegate = delegate
        serviceSearch.start()
    }

    func stopDiscovery() {
        serviceSearch.stop()
        discoveryDelegate = nil
    }

    func connect(to tv: SamsungTV, remoteName: String) -> AsyncStream<TVConnectionState> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(.connecting)
            connectionState = .connecting
            pinRequired = false

            guard let service = servicesByIP[tv.ipAddress] else {
                continuation.yield(.error(.connectionFailed("SmartView service not found. Please rediscover TV.")))
                continuation.finish()
                return
            }

            self.service = service
            self.lastTV = tv
            self.lastRemoteName = remoteName

            let channelURI = "com.samsung.multiscreen.samsungtvremote"
            let channel = service.createChannel(channelURI)
            self.channel = channel
            channel.delegate = self
            self.didSignalConnected = false

            var attributes: [String: String] = ["name": remoteName]
            if let pendingPin, !pendingPin.isEmpty {
                attributes["pin"] = pendingPin
            }

            print("[TVDBG][SmartView] connect uri=\(service.uri) channelURI=\(channelURI) attrs=\(attributes)")
            channel.connect(attributes) { [weak self] _, error in
                guard let self else { return }
                if let error {
                    self.emitError(error)
                    return
                }
                self.scheduleConnected()
            }

            continuation.onTermination = { _ in
                self.disconnect()
            }
        }
    }

    func sendKey(_ key: RemoteKey, command: String) async throws {
        guard case .connected = connectionState else {
            throw TVError.notConnected
        }
        guard let channel else {
            throw TVError.notConnected
        }

        let payload: [String: AnyObject] = [
            "Cmd": command as AnyObject,
            "DataOfCmd": key.rawValue as AnyObject,
            "Option": "false" as AnyObject,
            "TypeOfRemote": "SendRemoteKey" as AnyObject
        ]
        channel.publish(
            event: "KeyInput",
            message: payload as NSDictionary,
            target: MessageTarget.Host.rawValue as NSString
        )
        print("[TVDBG][SmartView] send key event=KeyInput key=\(key.rawValue)")
    }

    func submitPin(_ pin: String) async throws {
        guard let tv = lastTV else {
            throw TVError.notConnected
        }

        pendingPin = pin
        _ = connect(to: tv, remoteName: lastRemoteName)
    }

    func disconnect() {
        channel?.disconnect(nil)
        channel = nil
        service = nil
        didSignalConnected = false
        pinRequired = false
        pendingPin = nil
        connectionState = .disconnected
        continuation?.yield(.disconnected)
        continuation?.finish()
        continuation = nil
    }

    func probeKeyEvents() {
        guard let channel else { return }
        let payload: [String: AnyObject] = [
            "Cmd": "Click" as AnyObject,
            "DataOfCmd": "KEY_MUTE" as AnyObject,
            "Option": "false" as AnyObject,
            "TypeOfRemote": "SendRemoteKey" as AnyObject
        ]
        let variants = [
            "KeyInput",
            "remoteControl",
            "ed.eapKeyInput",
            "ed.sendKey",
            "SendRemoteKey",
            "control"
        ]
        Task {
            for event in variants {
                print("[TVDBG][SmartView] probe event=\(event)")
                channel.publish(
                    event: event,
                    message: payload as NSDictionary,
                    target: MessageTarget.Host.rawValue as NSString
                )
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func extractHost(from uriString: String) -> String {
        if let url = URL(string: uriString), let host = url.host {
            return host
        }
        if uriString.contains("://"), let hostPart = uriString.split(separator: "/").dropFirst(2).first {
            return String(hostPart).split(separator: ":").first.map(String.init) ?? ""
        }
        return uriString.split(separator: ":").first.map(String.init) ?? uriString
    }

    private func isPinRequiredError(_ reason: String) -> Bool {
        let lower = reason.lowercased()
        return lower.contains("pin") || lower.contains("unauthorized") || lower.contains("401")
    }

    private func emitConnected() {
        if pinRequired {
            pinRequired = false
            pendingPin = nil
        }
        connectionState = .connected
        print("[TVDBG][SmartView] connected")
        continuation?.yield(.connected)
    }

    private func scheduleConnected() {
        guard !didSignalConnected else { return }
        didSignalConnected = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.emitConnected()
        }
    }

    private func emitDisconnected() {
        connectionState = .disconnected
        print("[TVDBG][SmartView] disconnected")
        continuation?.yield(.disconnected)
        continuation?.finish()
        continuation = nil
    }

    private func emitError(_ error: NSError) {
        let reason = error.localizedDescription
        print("[TVDBG][SmartView][ERROR] domain=\(error.domain) code=\(error.code) reason=\(reason)")
        if isPinRequiredError(reason) {
            pinRequired = true
            connectionState = .pinRequired(countdown: 60)
            continuation?.yield(.pinRequired(countdown: 60))
            return
        }

        connectionState = .error(.connectionFailed(reason))
        continuation?.yield(.error(.connectionFailed(reason)))
    }
}

extension SmartViewSDKClient: ChannelDelegate {
    func onConnect(_ client: ChannelClient?, error: NSError?) {
        _ = client
        if let error {
            emitError(error)
        } else {
            scheduleConnected()
        }
    }

    func onReady() {
        scheduleConnected()
    }

    func onDisconnect(_ client: ChannelClient?, error: NSError?) {
        _ = client
        _ = error
        emitDisconnected()
    }

    func onClientConnect(_ client: ChannelClient) {
        _ = client
    }

    func onClientDisconnect(_ client: ChannelClient) {
        _ = client
    }

    func onError(_ error: NSError) {
        emitError(error)
    }

    func onMessage(_ message: Message) {
        _ = message
    }

    func onData(_ message: Message, payload: Data) {
        _ = message
        _ = payload
    }
}

private final class DiscoveryDelegate: NSObject, ServiceSearchDelegate {
    private let onFound: (Service) -> Void

    init(onFound: @escaping (Service) -> Void) {
        self.onFound = onFound
    }

    func onServiceFound(_ service: Service) {
        onFound(service)
    }

    func onServiceLost(_ service: Service) {
        _ = service
    }
}

#else

final class SmartViewSDKClient: ObservableObject {
    @Published var connectionState: TVConnectionState = .disconnected
    @Published var pinRequired = false

    var isSDKAvailable: Bool { false }

    func startDiscovery(onFound: @escaping (SamsungTV) -> Void) {
        _ = onFound
    }

    func stopDiscovery() {}

    func connect(to tv: SamsungTV, remoteName: String) -> AsyncStream<TVConnectionState> {
        _ = tv
        _ = remoteName
        return AsyncStream { continuation in
            continuation.yield(.error(.unsupportedProtocol("SmartView.xcframework is not linked.")))
            continuation.finish()
        }
    }

    func sendKey(_ key: RemoteKey, command: String) async throws {
        _ = key
        _ = command
        throw TVError.unsupportedProtocol("SmartView.xcframework is not linked.")
    }

    func submitPin(_ pin: String) async throws {
        _ = pin
        throw TVError.unsupportedProtocol("SmartView.xcframework is not linked.")
    }

    func disconnect() {
        connectionState = .disconnected
    }
}

#endif
