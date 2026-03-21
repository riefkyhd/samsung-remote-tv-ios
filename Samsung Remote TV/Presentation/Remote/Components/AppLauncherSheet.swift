import SwiftUI

struct AppLauncherSheet: View {
    let apps: [TVApp]
    let launch: (TVApp) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Curated shortcuts for common streaming apps.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(apps) { app in
                            Button {
                                launch(app)
                            } label: {
                                VStack(spacing: 8) {
                                    AsyncImage(url: app.iconURL) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFit()
                                        default:
                                            Image(systemName: "tv")
                                                .resizable()
                                                .scaledToFit()
                                                .padding(10)
                                        }
                                    }
                                    .frame(width: 68, height: 68)
                                    .background(Color.gray.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                    Text(app.name)
                                        .font(.caption)
                                }
                                .frame(width: 92)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Quick Launch")
        }
    }
}
