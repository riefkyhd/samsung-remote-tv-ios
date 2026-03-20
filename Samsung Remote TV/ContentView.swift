import SwiftUI

struct ContentView: View {
    var body: some View {
        AppRouter()
            .environment(AppDependencies())
    }
}

#Preview {
    ContentView()
}
