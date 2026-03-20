import SwiftUI

@main
struct SamsungTVRemoteApp: App {
    @State private var dependencies = AppDependencies()
    @AppStorage("colorScheme") private var colorScheme = "system"

    init() {
        SpcCrypto.runCryptoTest()
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environment(dependencies)
                .preferredColorScheme(preferredScheme)
        }
    }

    private var preferredScheme: ColorScheme? {
        switch colorScheme {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}
