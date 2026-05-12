import SwiftUI

struct MiniMapView: View {
    let nodePositions: [CGPoint]
    let viewportRect: CGRect
    let allBounds: CGRect

    @State private var dragOffset: CGSize = .zero
    @GestureState private var liveDrag: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.7)
                ForEach(0..<nodePositions.count, id: \.self) { i in
                    let p = nodePositions[i]
                    let mapped = map(point: p, in: geo.size)
                    Circle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 2, height: 2)
                        .position(mapped)
                }
                let vpRect = mapRect(viewportRect, in: geo.size)
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .background(Color.accentColor.opacity(0.08))
                    .frame(width: vpRect.width, height: vpRect.height)
                    .position(x: vpRect.midX, y: vpRect.midY)
            }
        }
        .frame(width: 150, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .offset(x: dragOffset.width + liveDrag.width,
                y: dragOffset.height + liveDrag.height)
        .gesture(
            DragGesture()
                .updating($liveDrag) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    dragOffset.width += value.translation.width
                    dragOffset.height += value.translation.height
                }
        )
    }

    private func map(point p: CGPoint, in size: CGSize) -> CGPoint {
        let bw = max(allBounds.width, 1)
        let bh = max(allBounds.height, 1)
        let nx = (p.x - allBounds.minX) / bw
        let ny = (p.y - allBounds.minY) / bh
        return CGPoint(x: nx * size.width, y: (1 - ny) * size.height)
    }

    private func mapRect(_ r: CGRect, in size: CGSize) -> CGRect {
        let topLeft = map(point: CGPoint(x: r.minX, y: r.maxY), in: size)
        let bottomRight = map(point: CGPoint(x: r.maxX, y: r.minY), in: size)
        return CGRect(x: topLeft.x, y: topLeft.y,
                      width: bottomRight.x - topLeft.x,
                      height: bottomRight.y - topLeft.y)
    }
}
