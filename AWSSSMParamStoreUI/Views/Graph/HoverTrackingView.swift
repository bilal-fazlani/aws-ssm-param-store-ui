import SwiftUI
import AppKit
import SpriteKit

struct HoverTrackingSpriteView: NSViewRepresentable {
    let scene: GraphScene

    func makeNSView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.presentScene(scene)
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        let area = NSTrackingArea(rect: .zero,
                                  options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
                                  owner: context.coordinator,
                                  userInfo: nil)
        view.addTrackingArea(area)
        context.coordinator.trackedView = view
        context.coordinator.scene = scene
        return view
    }

    func updateNSView(_ nsView: SKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSResponder {
        weak var trackedView: SKView?
        weak var scene: GraphScene?

        override func mouseMoved(with event: NSEvent) {
            guard let view = trackedView, let scene = scene else { return }
            let pointInView = view.convert(event.locationInWindow, from: nil)
            let pointInScene = scene.convertPoint(fromView: pointInView)
            scene.handleMouseMoved(toScenePoint: pointInScene)
        }
    }
}
