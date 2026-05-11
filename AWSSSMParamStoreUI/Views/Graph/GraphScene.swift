import SpriteKit
import SwiftUI

final class GraphScene: SKScene {
    var theme: GraphTheme = GraphTheme(colorScheme: .dark) {
        didSet { applyTheme() }
    }

    private let cameraNode = SKCameraNode()
    private let container = SKNode()
    private var nodeSprites: [String: GraphNodeSprite] = [:]
    private var edgeSprites: [GraphEdge] = []
    private var centerField: SKFieldNode!

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        physicsWorld.gravity = .zero
        backgroundColor = theme.canvasBackground

        addChild(container)
        addChild(cameraNode)
        camera = cameraNode

        centerField = SKFieldNode.radialGravityField()
        centerField.strength = -0.6
        centerField.falloff = -1
        centerField.position = .zero
        centerField.categoryBitMask = 0x1
        addChild(centerField)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func applyTheme() {
        backgroundColor = theme.canvasBackground
        for edge in edgeSprites { edge.strokeColor = theme.edgeColor }
        // Sprite recoloring lands in Task 22.
    }

    override func update(_ currentTime: TimeInterval) {
        for edge in edgeSprites {
            edge.updatePath()
        }
    }
}
