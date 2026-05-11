import Testing
import Foundation
@testable import AWSSSMParamStoreUI

@Suite struct GraphSVGExporterTests {
    @Test func exports_well_formed_svg_with_circle_per_node_and_line_per_edge() {
        let nodes: [GraphSVGExporter.PositionedNode] = [
            .init(id: "a", x: 0, y: 0, radius: 18, fillHex: "#10b981", label: "home"),
            .init(id: "b", x: 100, y: 0, radius: 12, fillHex: "#f59e0b", label: "/app1")
        ]
        let edges: [GraphSVGExporter.PositionedEdge] = [
            .init(x1: 0, y1: 0, x2: 100, y2: 0)
        ]
        let svg = GraphSVGExporter.export(nodes: nodes, edges: edges,
                                          edgeColorHex: "#888888",
                                          backgroundHex: "#141414")

        #expect(svg.hasPrefix("<?xml"))
        #expect(svg.contains("<svg"))
        #expect(svg.contains("</svg>"))
        // 2 circles
        #expect(svg.components(separatedBy: "<circle ").count - 1 == 2)
        // 1 line
        #expect(svg.components(separatedBy: "<line ").count - 1 == 1)
        // labels rendered as <text>
        #expect(svg.contains(">/app1<"))
        #expect(svg.contains("fill=\"#10b981\""))
        #expect(svg.contains("fill=\"#141414\""))
    }

    @Test func empty_input_produces_valid_empty_svg() {
        let svg = GraphSVGExporter.export(nodes: [], edges: [],
                                          edgeColorHex: "#888888",
                                          backgroundHex: "#ffffff")
        #expect(svg.contains("<svg"))
        #expect(svg.contains("</svg>"))
        #expect(!svg.contains("<circle"))
        #expect(!svg.contains("<line"))
    }
}
