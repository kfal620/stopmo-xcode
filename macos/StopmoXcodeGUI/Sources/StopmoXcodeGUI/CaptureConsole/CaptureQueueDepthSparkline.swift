import SwiftUI

/// Data/view model for queue depth sparkline.
struct QueueDepthSparkline: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 1, 1)
            let width = geo.size.width
            let height = geo.size.height
            let denom = max(values.count - 1, 1)

            ZStack {
                RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))

                Path { path in
                    guard !values.isEmpty else {
                        return
                    }
                    for (idx, value) in values.enumerated() {
                        let x = width * CGFloat(idx) / CGFloat(denom)
                        let y = height - (height * CGFloat(value) / CGFloat(maxValue))
                        if idx == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                Path { path in
                    guard !values.isEmpty else {
                        return
                    }
                    path.move(to: CGPoint(x: 0, y: height))
                    for (idx, value) in values.enumerated() {
                        let x = width * CGFloat(idx) / CGFloat(denom)
                        let y = height - (height * CGFloat(value) / CGFloat(maxValue))
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(Color.orange.opacity(0.14))
            }
        }
    }
}
