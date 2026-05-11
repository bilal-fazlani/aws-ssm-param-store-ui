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

    var onNavigateToLeaf: ((String) -> Void)?
    var onRevealInExplorer: ((String) -> Void)?
    var onSettleChange: ((Bool) -> Void)?

    private var isSettled: Bool = false {
        didSet {
            if isSettled != oldValue { onSettleChange?(isSettled) }
        }
    }

    private var lowEnergyFrames: Int = 0
    private let energyThreshold: CGFloat = 0.5
    private let framesToFreeze: Int = 30

    private var dragLastPoint: CGPoint?
    private var mouseDownPoint: CGPoint?
    private var mouseDownTime: TimeInterval = 0

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
        guard let vm = viewModel else { return }
        for (id, sprite) in nodeSprites {
            guard let snapshotNode = vm.snapshot.nodes.first(where: { $0.id == id }) else { continue }
            sprite.recolor(snapshotNode: snapshotNode, theme: theme)
        }
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
                isSettled = true
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
        isSettled = false
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.location(in: self)
        mouseDownTime = event.timestamp
        dragLastPoint = event.location(in: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = dragLastPoint else { return }
        let now = event.location(in: self)
        let dx = now.x - last.x
        let dy = now.y - last.y
        cameraNode.position = CGPoint(x: cameraNode.position.x - dx,
                                      y: cameraNode.position.y - dy)
        dragLastPoint = now
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragLastPoint = nil; mouseDownPoint = nil }
        guard let down = mouseDownPoint else { return }
        let up = event.location(in: self)
        let dist = hypot(up.x - down.x, up.y - down.y)
        let elapsed = event.timestamp - mouseDownTime
        if dist < 4 && elapsed < 0.4 {
            if event.clickCount >= 2 {
                handleDoubleClick(at: up)
            } else {
                handleSingleClick(at: up)
            }
        }
    }

    private func sprite(at point: CGPoint) -> GraphNodeSprite? {
        let hit = nodes(at: point).compactMap { node -> GraphNodeSprite? in
            var n: SKNode? = node
            while n != nil {
                if let g = n as? GraphNodeSprite { return g }
                n = n?.parent
            }
            return nil
        }
        return hit.first
    }

    private func handleSingleClick(at point: CGPoint) {
        guard let vm = viewModel else { return }
        if let sprite = sprite(at: point) {
            vm.selectedNodeId = sprite.snapshotNodeId
        } else {
            vm.selectedNodeId = nil
        }
        refreshSelectionVisuals()
    }

    private func handleDoubleClick(at point: CGPoint) {
        guard let sprite = sprite(at: point) else { return }
        switch sprite.kind {
        case .leaf:
            onNavigateToLeaf?(sprite.snapshotNodeId)
        case .folder:
            viewModel?.toggleCollapse(folderId: sprite.snapshotNodeId)
            rebuild()
        case .home:
            break
        }
    }

    func refreshSelectionVisuals() {
        let selected = viewModel?.selectedNodeId
        let dimming = selected != nil
        for (id, sprite) in nodeSprites {
            sprite.setSelected(id == selected)
            sprite.setDimmed(dimming && id != selected)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = event.location(in: self)
        guard let sprite = sprite(at: point), let view = self.view else { return }
        let menu = NSMenu()
        switch sprite.kind {
        case .folder:
            let id = sprite.snapshotNodeId
            let isCollapsed = viewModel?.collapsedFolderIds.contains(id) == true
            let collapseExpand = NSMenuItem(
                title: isCollapsed ? "Expand" : "Collapse",
                action: #selector(menuToggleCollapse(_:)),
                keyEquivalent: ""
            )
            collapseExpand.target = self
            collapseExpand.representedObject = id
            menu.addItem(collapseExpand)
            menu.addItem(.separator())
            let reveal = NSMenuItem(title: "View in Explorer",
                                    action: #selector(menuRevealInExplorer(_:)),
                                    keyEquivalent: "")
            reveal.target = self
            reveal.representedObject = id
            menu.addItem(reveal)
        case .leaf:
            let reveal = NSMenuItem(title: "View in Explorer",
                                    action: #selector(menuRevealInExplorer(_:)),
                                    keyEquivalent: "")
            reveal.target = self
            reveal.representedObject = sprite.snapshotNodeId
            menu.addItem(reveal)
        case .home:
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func menuToggleCollapse(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        viewModel?.toggleCollapse(folderId: id)
        rebuild()
    }

    @objc private func menuRevealInExplorer(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onRevealInExplorer?(id)
    }

    func applySearchHighlights() {
        guard let vm = viewModel else { return }
        let matches = vm.matchingNodeIds
        let hasSearch = !matches.isEmpty
        for (id, sprite) in nodeSprites {
            if hasSearch {
                let isMatch = matches.contains(id)
                sprite.setSearchHighlighted(isMatch)
                sprite.setDimmed(!isMatch)
            } else {
                sprite.setSearchHighlighted(false)
                let selected = vm.selectedNodeId
                sprite.setDimmed(selected != nil && selected != id)
            }
        }
    }

    func fitToMatches(animated: Bool) {
        guard let vm = viewModel else { return }
        let matches = vm.matchingNodeIds
        guard !matches.isEmpty else { return }
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for id in matches {
            guard let s = nodeSprites[id] else { continue }
            minX = min(minX, s.position.x); minY = min(minY, s.position.y)
            maxX = max(maxX, s.position.x); maxY = max(maxY, s.position.y)
        }
        let pad: CGFloat = 60
        let w = (maxX - minX) + 2 * pad
        let h = (maxY - minY) + 2 * pad
        let viewSize = view?.bounds.size ?? size
        let scale = max(w / viewSize.width, h / viewSize.height, 0.1)
        let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        cameraNode.run(SKAction.group([
            SKAction.move(to: center, duration: animated ? 0.3 : 0),
            SKAction.scale(to: max(0.1, min(4.0, scale)), duration: animated ? 0.3 : 0)
        ]))
    }

    struct MiniMapSnapshot {
        let nodePositions: [CGPoint]
        let allBounds: CGRect
        let viewport: CGRect
    }

    func miniMapSnapshot() -> MiniMapSnapshot {
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        var positions: [CGPoint] = []
        positions.reserveCapacity(nodeSprites.count)
        for sprite in nodeSprites.values {
            positions.append(sprite.position)
            minX = min(minX, sprite.position.x); minY = min(minY, sprite.position.y)
            maxX = max(maxX, sprite.position.x); maxY = max(maxY, sprite.position.y)
        }
        let bounds = (positions.isEmpty)
            ? CGRect(x: -100, y: -100, width: 200, height: 200)
            : CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let viewSize = view?.bounds.size ?? size
        let halfW = viewSize.width * cameraNode.xScale * 0.5
        let halfH = viewSize.height * cameraNode.yScale * 0.5
        let vp = CGRect(x: cameraNode.position.x - halfW,
                        y: cameraNode.position.y - halfH,
                        width: halfW * 2,
                        height: halfH * 2)
        return MiniMapSnapshot(nodePositions: positions, allBounds: bounds, viewport: vp)
    }

    func exportCurrentSceneAsSVG() -> String {
        let posNodes: [GraphSVGExporter.PositionedNode] = nodeSprites.values.map { sprite in
            let snapshotNode = viewModel?.snapshot.nodes.first(where: { $0.id == sprite.snapshotNodeId })
            let color = snapshotNode.map { GraphNodeSprite.color(for: $0, theme: theme) } ?? .gray
            return GraphSVGExporter.PositionedNode(
                id: sprite.snapshotNodeId,
                x: Double(sprite.position.x),
                y: Double(-sprite.position.y),
                radius: Double(GraphNodeSprite.radius(for: sprite.kind)),
                fillHex: color.toHex(),
                label: snapshotNode?.label ?? ""
            )
        }
        let posEdges: [GraphSVGExporter.PositionedEdge] = edgeSprites.compactMap { edge in
            guard let from = edge.fromNode, let to = edge.toNode else { return nil }
            return GraphSVGExporter.PositionedEdge(
                x1: Double(from.position.x), y1: Double(-from.position.y),
                x2: Double(to.position.x), y2: Double(-to.position.y)
            )
        }
        return GraphSVGExporter.export(
            nodes: posNodes, edges: posEdges,
            edgeColorHex: theme.edgeColor.toHex(),
            backgroundHex: theme.canvasBackground.toHex()
        )
    }

    func handleMouseMoved(toScenePoint point: CGPoint) {
        guard let vm = viewModel else { return }
        let hovered = sprite(at: point)?.snapshotNodeId
        if hovered == vm.hoveredNodeId { return }
        if let prevId = vm.hoveredNodeId, let prev = nodeSprites[prevId], prev.kind != .home {
            prev.setLabelVisible(cameraNode.xScale < 0.6)
        }
        vm.hoveredNodeId = hovered
        if let id = hovered, let sprite = nodeSprites[id], sprite.kind != .home {
            sprite.setLabelVisible(true)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let zoomFactor: CGFloat = 1 + CGFloat(event.deltaY) * 0.04
        applyZoom(zoomFactor, around: event.location(in: self))
    }

    override func magnify(with event: NSEvent) {
        let zoomFactor: CGFloat = 1 + event.magnification
        applyZoom(zoomFactor, around: event.location(in: self))
    }

    private func applyZoom(_ factor: CGFloat, around focal: CGPoint) {
        let oldScale = cameraNode.xScale
        let newScale = max(0.1, min(4.0, oldScale * factor))
        if newScale == oldScale { return }
        let dx = (focal.x - cameraNode.position.x) * (1 - newScale / oldScale)
        let dy = (focal.y - cameraNode.position.y) * (1 - newScale / oldScale)
        cameraNode.position.x += dx
        cameraNode.position.y += dy
        cameraNode.setScale(newScale)
        updateLabelLOD()
    }

    private func updateLabelLOD() {
        let zoomedIn = cameraNode.xScale < 0.6
        for sprite in nodeSprites.values where sprite.kind != .home {
            if sprite.snapshotNodeId != viewModel?.hoveredNodeId {
                sprite.setLabelVisible(zoomedIn)
            }
        }
    }

    func fitToView(animated: Bool) {
        guard !nodeSprites.isEmpty else { return }
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for sprite in nodeSprites.values {
            minX = min(minX, sprite.position.x); minY = min(minY, sprite.position.y)
            maxX = max(maxX, sprite.position.x); maxY = max(maxY, sprite.position.y)
        }
        let pad: CGFloat = 60
        let w = (maxX - minX) + 2 * pad
        let h = (maxY - minY) + 2 * pad
        let viewSize = view?.bounds.size ?? size
        let scale = max(w / viewSize.width, h / viewSize.height, 0.1)
        let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let move = SKAction.move(to: center, duration: animated ? 0.3 : 0)
        let zoom = SKAction.scale(to: max(0.1, min(4.0, scale)), duration: animated ? 0.3 : 0)
        cameraNode.run(SKAction.group([move, zoom])) { [weak self] in self?.updateLabelLOD() }
    }

    func resetZoom(animated: Bool) {
        let move = SKAction.move(to: .zero, duration: animated ? 0.3 : 0)
        let zoom = SKAction.scale(to: 1.0, duration: animated ? 0.3 : 0)
        cameraNode.run(SKAction.group([move, zoom])) { [weak self] in self?.updateLabelLOD() }
    }
}

private extension NSColor {
    func toHex() -> String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
