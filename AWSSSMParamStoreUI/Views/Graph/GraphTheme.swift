import SwiftUI
import AppKit

struct GraphTheme: Equatable {
    let colorScheme: ColorScheme

    var canvasBackground: NSColor {
        colorScheme == .dark ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 0.97, alpha: 1)
    }

    var homeNodeColor: NSColor { NSColor.systemGreen }

    var edgeColor: NSColor {
        colorScheme == .dark
            ? NSColor.white.withAlphaComponent(0.18)
            : NSColor.black.withAlphaComponent(0.18)
    }

    var labelColor: NSColor {
        colorScheme == .dark ? .white : .black
    }

    var labelBackground: NSColor {
        colorScheme == .dark
            ? NSColor.black.withAlphaComponent(0.85)
            : NSColor.white.withAlphaComponent(0.92)
    }

    var selectionRingColor: NSColor { NSColor.systemBlue }

    var searchHighlightRingColor: NSColor { NSColor.systemTeal }

    private static let clusterPalette: [NSColor] = [
        NSColor.systemOrange,
        NSColor.systemPink,
        NSColor.systemPurple,
        NSColor.systemTeal,
        NSColor.systemIndigo,
        NSColor.systemYellow,
        NSColor.systemMint,
        NSColor.systemRed
    ]

    func clusterColor(forIndex index: Int) -> NSColor {
        Self.clusterPalette[((index % Self.clusterPalette.count) + Self.clusterPalette.count) % Self.clusterPalette.count]
    }
}
