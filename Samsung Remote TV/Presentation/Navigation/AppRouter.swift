import SwiftUI

enum AppRoute: Hashable {
    case settings
}

struct AppRouter: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            DiscoveryView(
                viewModel: DiscoveryViewModel(dependencies: dependencies),
                onSelectTV: { tv in
                    path.append(tv)
                },
                onOpenSettings: {
                    path.append(AppRoute.settings)
                }
            )
            .navigationDestination(for: SamsungTV.self) { tv in
                RemoteView(viewModel: RemoteViewModel(tv: tv, dependencies: dependencies))
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .settings:
                    SettingsView(viewModel: SettingsViewModel(dependencies: dependencies))
                }
            }
        }
    }
}

#Preview {
    AppRouter()
        .environment(AppDependencies())
}
