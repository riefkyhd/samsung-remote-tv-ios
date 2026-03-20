import SwiftUI

struct DPadController: View {
    let action: (RemoteKey) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size * 0.45

            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.12))
                Circle()
                    .stroke(Color.gray.opacity(0.35), lineWidth: 2)

                DPadTrianglesShape()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)

                Circle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: size * 0.35, height: size * 0.35)
                    .overlay(Text("OK").font(.headline))
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y
                        let distance = sqrt(dx * dx + dy * dy)

                        if distance < radius * 0.25 {
                            action(.KEY_ENTER)
                            return
                        }

                        let angle = atan2(dy, dx)
                        switch angle {
                        case (-.pi / 4)...(.pi / 4):
                            action(.KEY_RIGHT)
                        case (.pi / 4)...(3 * .pi / 4):
                            action(.KEY_DOWN)
                        case (-3 * .pi / 4)...(-.pi / 4):
                            action(.KEY_UP)
                        default:
                            action(.KEY_LEFT)
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("D-Pad")
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct DPadTrianglesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)

        path.move(to: CGPoint(x: center.x, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: center.y))
        path.closeSubpath()

        path.move(to: CGPoint(x: rect.minX, y: center.y))
        path.addLine(to: CGPoint(x: rect.maxX, y: center.y))
        path.move(to: CGPoint(x: center.x, y: rect.minY))
        path.addLine(to: CGPoint(x: center.x, y: rect.maxY))

        return path
    }
}

#Preview {
    DPadController { _ in }
        .frame(width: 220)
        .padding()
}
