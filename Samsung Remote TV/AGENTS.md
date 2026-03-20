# AGENTS.md — Samsung Smart TV Remote iOS App

> Codex reads this file automatically at the start of every session.
> Place this file in the **root** of the Xcode project directory (alongside `SamsungTVRemote.xcodeproj`).
> Do not delete or rename this file.

---

## 📋 Project Overview

**App Name:** Samsung TV Remote
**Bundle ID:** `com.yourcompany.SamsungTVRemote`
**Project File:** `SamsungTVRemote.xcodeproj`
**Purpose:** A fully functional Samsung Smart TV remote control iOS app communicating with Samsung Tizen Smart TVs (2013–2025) over local Wi-Fi using the Samsung WebSocket API.
**Platform:** iOS 17.0+
**Language:** Swift 5.10+ — no Objective-C source files
**UI Framework:** SwiftUI
**Xcode:** 16.0+

---

## 🧱 Architecture Rules — Non-Negotiable

This project uses **Clean Architecture** with **MVVM** in the presentation layer.

```
Presentation  →  Domain  ←  Data
(SwiftUI Views    (UseCases,     (WebSocket, REST,
 @Observable       Models,        Discovery,
 ViewModels)       Repository     UserDefaults)
                   Protocols)
```

### Strict Layer Rules

| Rule | Enforcement |
|---|---|
| **Domain is pure Swift** | Zero imports of `UIKit`, `SwiftUI`, any SPM package, or `Foundation` subclasses |
| **No cross-layer skipping** | ViewModels call Use Cases only — never `Repository` or storage directly |
| **Repository protocol in Domain** | `TVRepository.swift` lives in `Domain/Repositories/` — implementation in `Data/Repositories/` |
| **No callbacks** | All async uses `async`/`await`, `AsyncStream`, or `AsyncSequence` — no completion handlers in new code |
| **`@Observable` only** | All ViewModels use the `@Observable` macro (iOS 17). No `ObservableObject`, no `@Published` |
| **`@MainActor` for UI state** | All `@Observable` ViewModels are `@MainActor`. Use `await MainActor.run {}` when needed |
| **No GCD** | No `DispatchQueue.main.async`. Use `async`/`await` and `@MainActor` only |
| **Actors for shared mutable state** | `SamsungTVWebSocketClient` is an `actor`. Any class with concurrent state access is an `actor` |
| **No `UserDefaults` in ViewModels** | Only `TVUserDefaultsStorage` (Data layer) reads/writes UserDefaults |
| **SPM only** | No CocoaPods, no Carthage. All dependencies via Swift Package Manager |

---

## 🌐 Samsung TV API — Codex Must Know This

### Endpoint Pattern

```
# Tizen 2016+ (self-signed SSL)
wss://{TV_IP}:8002/api/v2/channels/samsung.remote.control?name={BASE64_NAME}&token={TOKEN}

# Legacy 2013–2015 (plain WS)
ws://{TV_IP}:8001/api/v2/channels/samsung.remote.control?name={BASE64_NAME}

# REST detection — always probe first to identify Samsung TV
http://{TV_IP}:8001/api/v2/
```

`BASE64_NAME` = `Data("SamsungTVRemote".utf8).base64EncodedString()`

### Remote Key JSON

```json
{
  "method": "ms.remote.control",
  "params": {
    "Cmd": "Click",
    "DataOfCmd": "KEY_VOLUP",
    "Option": "false",
    "TypeOfRemote": "SendRemoteKey"
  }
}
```

`Cmd`: `Click` | `Press` (long-press start) | `Release` (long-press end)

### Pairing Flow

1. Connect WebSocket without `?token=` → TV shows "Allow?" dialog
2. User accepts → TV sends: `{ "event": "ms.channel.connect", "data": { "token": "XXXXXXXX" } }`
3. Save token: `UserDefaults.standard.set(token, forKey: "token_\(macAddress)")`
4. All future connections: append `?token=\(token)` to URL
5. "Forget Token" → `UserDefaults.standard.removeObject(forKey: "token_\(macAddress)")`

### SSL Self-Signed Certificate (iOS URLSession)

```swift
// SamsungTVWebSocketClient (actor) must set itself as URLSession delegate.
// WARNING: Only safe for Samsung TV local LAN connections.

func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          let trust = challenge.protectionSpace.serverTrust else {
        completionHandler(.performDefaultHandling, nil)
        return
    }
    completionHandler(.useCredential, URLCredential(trust: trust))
}
```

`Info.plist` entry for legacy plain WS:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

### WebSocket Receive Loop Pattern

```swift
// Inside actor SamsungTVWebSocketClient
private func startReceiving() {
    Task { [weak self] in
        guard let self else { return }
        while !Task.isCancelled {
            do {
                let message = try await webSocketTask.receive()
                await handleMessage(message)
            } catch {
                await handleDisconnect(error: error)
                break
            }
        }
    }
}
```

### Reconnection Backoff

```swift
// Delay sequence (seconds): 1 → 2 → 4 → 8 → 16 → 30 (capped)
let delay = min(pow(2.0, Double(retryCount)), 30.0)
try await Task.sleep(for: .seconds(delay))
```

---

## 📡 TV Discovery Details

### IP Range Scan

```swift
// NetworkUtils.localIPAddress() → "192.168.1.105"
// Derive subnet → "192.168.1."
// withThrowingTaskGroup: spawn tasks for 1...254
// Each task: URLSession with 2s timeout → GET http://{ip}:8001/api/v2/
// Decode TVInfoDTO → map to SamsungTV
// Use actor-based DeduplicationSet to filter by MAC address
```

### Bonjour via NWBrowser

```swift
// Required Info.plist keys:
//   NSBonjourServices: ["_samsungctl._tcp", "_samsung-multiscreen._tcp"]
//   NSLocalNetworkUsageDescription: usage reason string

let browser = NWBrowser(for: .bonjour(type: "_samsungctl._tcp", domain: nil), using: .tcp)
browser.browseResultsChangedHandler = { results, _ in
    for result in results {
        if case .service(let name, _, let domain, _) = result.endpoint {
            // resolve IP, verify via REST, emit SamsungTV
        }
    }
}
browser.start(queue: .global())
```

### Wake on LAN

```swift
// Magic packet: [0xFF × 6] + [macBytes × 16] = 102 bytes
// Send UDP via NWConnection to:
//   NWEndpoint.hostPort(host: "255.255.255.255", port: 9)
//   NWEndpoint.hostPort(host: "255.255.255.255", port: 7)
// Validate MAC: regex "^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$"
```

---

## 🎨 SwiftUI Conventions

- **`@Observable` ViewModels** — `@MainActor` class, injected via `.environment()`, accessed with `@Environment(MyViewModel.self)`
- **D-Pad** — custom `Shape` using `Path` drawing four directional triangles + center circle. Tap detection via `DragGesture(minimumDistance: 0).onEnded` with angle calculation
- **Haptics** — `UIImpactFeedbackGenerator(style: .light).impactOccurred()` on all button taps
- **Long-press power** — `.simultaneousGesture(LongPressGesture(minimumDuration: 0.8).onEnded { _ in sendKey(.KEY_POWEROFF) })` combined with `.onTapGesture { sendKey(.KEY_POWER) }`
- **Landscape** — `GeometryReader` + `@Environment(\.horizontalSizeClass)` → if `.regular` render two-column `HStack`
- **Connection dot** — `Circle().fill(connectionColor).overlay(Circle().stroke(...)).animation(.easeInOut(duration: 0.5), value: connectionState)`
- **All strings** in `Localizable.strings` — zero hardcoded English strings in SwiftUI views
- **Accessibility** — all buttons have `.accessibilityLabel(Text(...))`. D-Pad zones have individual accessibility actions
- **No `NavigationView`** — use `NavigationStack` (iOS 16+) with typed `NavigationPath`
- Every View must have a `#Preview` macro block

---

## 🧪 Testing Conventions

### Swift Testing (Unit + Integration)

```swift
import Testing
@testable import SamsungTVRemote

@Suite("DiscoverTVsUseCase")
struct DiscoverTVsUseCaseTests {

    @Test("REST scan emits discovered TV on valid response")
    func restScanEmitsTV() async throws {
        let mockRepo = MockTVRepository()
        mockRepo.stubbedDiscoveredTVs = [SamsungTV.mock()]
        let sut = DiscoverTVsUseCase(repository: mockRepo)
        var results: [SamsungTV] = []
        for await tv in sut.execute() {
            results.append(tv)
        }
        #expect(results.count == 1)
        #expect(results[0].name == "Mock TV")
    }
}
```

### Mock Strategy

Use protocol-based mocks — no third-party mocking library:

```swift
// MockTVRepository.swift (test target only)
final class MockTVRepository: TVRepository {
    var stubbedDiscoveredTVs: [SamsungTV] = []
    var sendKeyCalled = false
    var lastSentKey: RemoteKey?

    func discoverTVs() -> AsyncStream<SamsungTV> {
        AsyncStream { continuation in
            for tv in stubbedDiscoveredTVs { continuation.yield(tv) }
            continuation.finish()
        }
    }

    func sendKey(_ key: RemoteKey) async throws {
        sendKeyCalled = true
        lastSentKey = key
    }
    // ... other protocol requirements
}
```

### XCTest UI Tests

```swift
import XCTest

final class DiscoveryViewUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"] // disable animations, inject mock data
        app.launch()
    }
}
```

Add `--uitesting` launch argument handling in `SamsungTVRemoteApp.swift` to inject mock dependencies.

### Coverage Target

| Group | Minimum |
|---|---|
| `Domain/UseCases/` | 90% |
| `Domain/Models/` | 80% |
| `Data/Repositories/` | 80% |
| `Data/Network/` | 75% |
| `Presentation/` | 60% |

Enable: `Edit Scheme → Test → Code Coverage → Gather coverage`

---

## 📁 Key File Reference

| File | Role |
|---|---|
| `RemoteKey.swift` | `enum RemoteKey: String` — all Samsung key codes |
| `TVConnectionState.swift` | `enum TVConnectionState` — `disconnected`, `connecting`, `pairing(countdown:Int)`, `connected`, `error(TVError)` |
| `TVError.swift` | `enum TVError: Error` — `notConnected`, `pairingRejected`, `pairingTimeout`, `connectionFailed(Error)`, `commandFailed(RemoteKey, Error)`, `invalidMacAddress`, `notOnWifi` |
| `SamsungTVWebSocketClient.swift` | `actor` — `URLSessionWebSocketTask` lifecycle, SSL delegate, token parsing, reconnection |
| `IPRangeScanner.swift` | `TaskGroup`-based concurrent subnet scan → `AsyncStream<SamsungTV>` |
| `BonjourDiscovery.swift` | `NWBrowser` wrapped in `AsyncStream<SamsungTV>` |
| `SSDPDiscovery.swift` | `NWConnection` UDP multicast → `AsyncStream<SamsungTV>` |
| `TVUserDefaultsStorage.swift` | `Codable` + `UserDefaults` for saved TVs and tokens |
| `TVRepositoryImpl.swift` | Merges all discovery streams, delegates to WebSocket client, uses storage |
| `AppRouter.swift` | `NavigationStack` + `NavigationPath` — `DiscoveryView` → `RemoteView(tv:)` → `SettingsView` |
| `AppDependencies.swift` | Constructs all data and domain layer objects, injected via `.environment()` |
| `QA_CHECKLIST.md` | Manual test cases — update as features change |

---

## 🚫 What Codex Must NOT Do

| ❌ Forbidden | ✅ Correct Alternative |
|---|---|
| `DispatchQueue.main.async { }` | `await MainActor.run { }` or `@MainActor` |
| `ObservableObject` / `@Published` | `@Observable` macro |
| `NavigationView` | `NavigationStack` |
| Completion handlers in new code | `async`/`await` |
| `Thread.sleep()` | `Task.sleep(for:)` |
| `fatalError("not implemented")` | Fully implement all functions |
| `UserDefaults` access in ViewModel | Route through `TVUserDefaultsStorage` in Data layer |
| UIKit imports in Domain layer | Pure Swift — Foundation primitives only |
| CocoaPods or Carthage | Swift Package Manager only |
| `class` ViewModels with `@Published` | `@Observable` class with `@MainActor` |
| Hardcoded strings in SwiftUI views | `Localizable.strings` with `String(localized:)` |
| `TODO` / stubs / truncated code | Every function fully implemented |
| `force_try` (`try!`) in production | Proper `do { try } catch { }` or `throws` propagation |
| `as!` force cast | `guard let x = y as? Type else { return }` |

---

## ✅ Definition of Done

A task is complete when **all** of the following are true:

1. **Builds:** `xcodebuild -scheme SamsungTVRemote build` exits 0 with zero warnings
2. **Unit tests pass:** `xcodebuild -scheme SamsungTVRemote test -destination 'platform=iOS Simulator,name=iPhone 16'` exits 0
3. **SwiftLint:** `swiftlint --strict` reports 0 violations
4. **SwiftFormat:** `swiftformat --lint .` reports 0 differences
5. **No force unwraps** in production code (`!` on Optional, `as!`, `try!`)
6. **No hardcoded strings** in SwiftUI views
7. **All `@Preview` macros** compile without errors
8. **`QA_CHECKLIST.md`** items for the feature are manually checked on real device

---

## 🔗 Reference Documentation

| Resource | URL |
|---|---|
| Samsung TV WebSocket API (community) | https://github.com/xchwarze/samsung-tv-ws-api |
| Samsung TV Key Codes (complete list) | https://github.com/jaruba/ha-samsungtv-tizen/blob/master/Key_codes.md |
| TVCommanderKit (Swift SDK reference) | https://github.com/wdesimini/TVCommanderKit |
| Samsung Developer — Smart TV | https://developer.samsung.com/smarttv |
| Apple URLSessionWebSocketTask | https://developer.apple.com/documentation/foundation/urlsessionwebsockettask |
| Apple NWBrowser (Bonjour) | https://developer.apple.com/documentation/network/nwbrowser |
| Apple Network.framework | https://developer.apple.com/documentation/network |
| Swift Testing framework | https://developer.apple.com/xcode/swift-testing/ |
| Local Network Privacy (iOS 14+) | https://developer.apple.com/news/?id=0oi77447 |
| Supporting local network privacy | https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription |
