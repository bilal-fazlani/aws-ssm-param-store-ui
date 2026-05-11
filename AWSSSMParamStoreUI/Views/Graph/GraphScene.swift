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

    weak var viewModel: GraphViewModel?

    private var lowEnergyFrames: Int = 0
    private let energyThreshold: CGFloat = 0.5
    private let framesToFreeze: Int = 30

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
        for edge in edgeSprites { edge.updatePath() }

        guard physicsWorld.speed > 0 else { return }
        var energy: CGFloat = 0
        for sprite in nodeSprites.values {
            guard let v = sprite.physicsBody?.velocity else { continue }
            energy += v.dx * v.dx + v.dy * v.dy
        }
        if energy < energyThreshold {
            lowEnergyFrames += 1
            if lowEnergyFrames >= framesToFreeze {
                physicsWorld.speed = 0
            }
        } else {
            lowEnergyFrames = 0
        }
    }

    func populate(viewModel: GraphViewModel) {
        self.viewModel = viewModel
        rebuild()
    }

    private func clearAll() {
        for sprite in nodeSprites.values { sprite.removeFromParent() }
        for edge in edgeSprites { edge.removeFromParent() }
        physicsWorld.removeAllJoints()
        nodeSprites.removeAll()
        edgeSprites.removeAll()
    }

    private func rebuild() {
        guard let vm = viewModel else { return }
        clearAll()

        for node in vm.visibleNodes {
            let sprite = GraphNodeSprite(snapshotNode: node, theme: theme)
            if node.kind == .home {
                sprite.position = .zero
            } else {
                let angle = Double.random(in: 0..<(2 * .pi))
                let r = Double.random(in: 60..<200)
                sprite.position = CGPoint(x: r * cos(angle), y: r * sin(angle))
            }
            if node.kind == .folder {
                let count = vm.hiddenDescendantCount(forFolderId: node.id)
                sprite.setBadge(count: count > 0 ? count : nil, theme: theme)
            }
            container.addChild(sprite)
            nodeSprites[node.id] = sprite
        }

        for edge in vm.visibleEdges {
            guard let a = nodeSprites[edge.fromId], let b = nodeSprites[edge.toId] else { continue }
            let edgeSprite = GraphEdge(from: a, to: b, theme: theme)
            container.addChild(edgeSprite)
            edgeSprites.append(edgeSprite)

            if let bodyA = a.physicsBody, let bodyB = b.physicsBody {
                let joint = SKPhysicsJointSpring.joint(
                    withBodyA: bodyA, bodyB: bodyB,
                    anchorA: a.position, anchorB: b.position
                )
                joint.frequency = 1.5
                joint.damping = 1.2
                physicsWorld.add(joint)
            }
        }

        cameraNode.position = .zero
        cameraNode.setScale(1.0)

        physicsWorld.speed = 1
        lowEnergyFrames = 0
    }
}
