import SpriteKit

final class GraphNodeSprite: SKNode {
    let snapshotNodeId: String
    let kind: GraphSnapshot.NodeKind
    let fullPath: String

    private let circle: SKShapeNode
    private let labelNode: SKLabelNode
    private let labelBackground: SKShapeNode
    private let selectionRing: SKShapeNode
    private var badgeNode: SKNode?

    init(snapshotNode: GraphSnapshot.Node, theme: GraphTheme) {
        self.snapshotNodeId = snapshotNode.id
        self.kind = snapshotNode.kind
        self.fullPath = snapshotNode.fullPath

        let radius = Self.radius(for: snapshotNode.kind)
        circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = Self.color(for: snapshotNode, theme: theme)
        circle.strokeColor = .white.withAlphaComponent(0.35)
        circle.lineWidth = 1.5

        labelNode = SKLabelNode(fontNamed: "SFMono-Regular")
        labelNode.fontSize = 9
        labelNode.fontColor = theme.labelColor
        labelNode.text = snapshotNode.label
        labelNode.verticalAlignmentMode = .center
        labelNode.horizontalAlignmentMode = .center
        labelNode.position = CGPoint(x: 0, y: radius + 12)

        let labelSize = labelNode.calculateAccumulatedFrame().size
        labelBackground = SKShapeNode(rectOf: CGSize(width: labelSize.width + 8, height: labelSize.height + 4),
                                      cornerRadius: 3)
        labelBackground.fillColor = theme.labelBackground
        labelBackground.strokeColor = .clear
        labelBackground.position = labelNode.position
        labelBackground.zPosition = -1

        selectionRing = SKShapeNode(circleOfRadius: radius + 4)
        selectionRing.strokeColor = theme.selectionRingColor
        selectionRing.lineWidth = 2.5
        selectionRing.fillColor = .clear
        selectionRing.glowWidth = 4
        selectionRing.isHidden = true

        super.init()

        addChild(selectionRing)
        addChild(circle)
        addChild(labelBackground)
        addChild(labelNode)
        labelNode.isHidden = true
        labelBackground.isHidden = true

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.linearDamping = 0.9
        body.angularDamping = 0.9
        body.allowsRotation = false
        body.mass = snapshotNode.kind == .home ? 100 : 1
        body.isDynamic = snapshotNode.kind != .home
        body.restitution = 0.05
        body.friction = 0
        body.categoryBitMask = 0x1
        body.collisionBitMask = 0x1
        body.contactTestBitMask = 0
        physicsBody = body
        name = snapshotNode.id
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    static func radius(for kind: GraphSnapshot.NodeKind) -> CGFloat {
        switch kind {
        case .home: return 20
        case .folder: return 12
        case .leaf: return 7
        }
    }

    static func color(for node: GraphSnapshot.Node, theme: GraphTheme) -> NSColor {
        switch node.kind {
        case .home: return theme.homeNodeColor
        case .folder, .leaf:
            let base = theme.clusterColor(forIndex: node.clusterIndex)
            return node.kind == .leaf ? base.withAlphaComponent(0.8) : base
        }
    }

    private lazy var searchRing: SKShapeNode = {
        let r = SKShapeNode(circleOfRadius: Self.radius(for: kind) + 3)
        r.strokeColor = NSColor.systemTeal
        r.lineWidth = 2
        r.fillColor = .clear
        r.glowWidth = 2
        r.isHidden = true
        addChild(r)
        return r
    }()

    func setSelected(_ selected: Bool) {
        selectionRing.isHidden = !selected
    }

    func setSearchHighlighted(_ highlighted: Bool) {
        searchRing.isHidden = !highlighted
    }

    func recolor(snapshotNode: GraphSnapshot.Node, theme: GraphTheme) {
        circle.fillColor = Self.color(for: snapshotNode, theme: theme)
        labelNode.fontColor = theme.labelColor
        labelBackground.fillColor = theme.labelBackground
        selectionRing.strokeColor = theme.selectionRingColor
    }

    func setLabelVisible(_ visible: Bool) {
        labelNode.isHidden = !visible
        labelBackground.isHidden = !visible
    }

    func setDimmed(_ dimmed: Bool) {
        circle.alpha = dimmed ? 0.15 : 1
    }

    func setBadge(count: Int?, theme: GraphTheme) {
        badgeNode?.removeFromParent()
        badgeNode = nil
        guard let count = count, count > 0 else { return }

        let label = SKLabelNode(fontNamed: "SFMono-Bold")
        label.fontSize = 8
        label.fontColor = theme.searchHighlightRingColor
        label.text = "+\(count)"
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center

        let size = label.calculateAccumulatedFrame().size
        let bg = SKShapeNode(rectOf: CGSize(width: size.width + 8, height: size.height + 4),
                             cornerRadius: 8)
        bg.fillColor = NSColor.black.withAlphaComponent(0.85)
        bg.strokeColor = theme.searchHighlightRingColor
        bg.lineWidth = 1.5

        let group = SKNode()
        group.position = CGPoint(x: Self.radius(for: kind) - 2, y: Self.radius(for: kind) - 2)
        group.zPosition = 5
        group.addChild(bg)
        group.addChild(label)
        addChild(group)
        badgeNode = group
    }
}
