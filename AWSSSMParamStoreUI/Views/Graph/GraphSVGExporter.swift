import Foundation

enum GraphSVGExporter {
    struct PositionedNode {
        let id: String
        let x: Double
        let y: Double
        let radius: Double
        let fillHex: String
        let label: String
    }

    struct PositionedEdge {
        let x1: Double
        let y1: Double
        let x2: Double
        let y2: Double
    }

    static func export(nodes: [PositionedNode],
                       edges: [PositionedEdge],
                       edgeColorHex: String,
                       backgroundHex: String) -> String {
        let margin: Double = 60
        let xs = nodes.map(\.x); let ys = nodes.map(\.y)
        let minX = (xs.min() ?? 0) - margin
        let minY = (ys.min() ?? 0) - margin
        let width = ((xs.max() ?? 0) - (xs.min() ?? 0)) + 2 * margin
        let height = ((ys.max() ?? 0) - (ys.min() ?? 0)) + 2 * margin

        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<svg xmlns=\"http://www.w3.org/2000/svg\" "
        out += "viewBox=\"\(minX) \(minY) \(width) \(height)\" "
        out += "width=\"\(width)\" height=\"\(height)\">\n"
        out += "<rect x=\"\(minX)\" y=\"\(minY)\" width=\"\(width)\" height=\"\(height)\" fill=\"\(backgroundHex)\"/>\n"

        for e in edges {
            out += "<line x1=\"\(e.x1)\" y1=\"\(e.y1)\" x2=\"\(e.x2)\" y2=\"\(e.y2)\" "
            out += "stroke=\"\(edgeColorHex)\" stroke-width=\"1\"/>\n"
        }
        for n in nodes {
            out += "<circle cx=\"\(n.x)\" cy=\"\(n.y)\" r=\"\(n.radius)\" fill=\"\(n.fillHex)\"/>\n"
            let escaped = escapeXML(n.label)
            out += "<text x=\"\(n.x)\" y=\"\(n.y - n.radius - 4)\" "
            out += "text-anchor=\"middle\" font-family=\"-apple-system, sans-serif\" "
            out += "font-size=\"10\" fill=\"\(edgeColorHex)\">\(escaped)</text>\n"
        }
        out += "</svg>\n"
        return out
    }

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
