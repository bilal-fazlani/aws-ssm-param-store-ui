import SpriteKit

final class GraphEdge: SKShapeNode {
    weak var fromNode: GraphNodeSprite?
    weak var toNode: GraphNodeSprite?

    init(from: GraphNodeSprite, to: GraphNodeSprite, theme: GraphTheme) {
        super.init()
        self.fromNode = from
        self.toNode = to
        strokeColor = theme.edgeColor
        lineWidth = 1
        zPosition = -10
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    func updatePath() {
        guard let from = fromNode, let to = toNode else { return }
        let path = CGMutablePath()
        path.move(to: from.position)
        path.addLine(to: to.position)
        self.path = path
    }
}
