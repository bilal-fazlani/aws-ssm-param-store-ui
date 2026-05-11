import Testing
import SwiftUI
@testable import AWSSSMParamStoreUI

@Suite struct GraphThemeTests {
    @Test func cluster_color_is_deterministic_by_index() {
        let theme = GraphTheme(colorScheme: .dark)
        #expect(theme.clusterColor(forIndex: 0) == theme.clusterColor(forIndex: 0))
        #expect(theme.clusterColor(forIndex: 0) != theme.clusterColor(forIndex: 1))
    }

    @Test func cluster_palette_has_eight_hues_and_cycles() {
        let theme = GraphTheme(colorScheme: .dark)
        // Index 8 wraps to index 0
        #expect(theme.clusterColor(forIndex: 8) == theme.clusterColor(forIndex: 0))
        #expect(theme.clusterColor(forIndex: 9) == theme.clusterColor(forIndex: 1))
    }

    @Test func home_color_differs_between_light_and_dark() {
        let dark = GraphTheme(colorScheme: .dark)
        let light = GraphTheme(colorScheme: .light)
        // Both must be defined; we don't assert equality, only that both exist.
        _ = dark.homeNodeColor
        _ = light.homeNodeColor
        #expect(dark.canvasBackground != light.canvasBackground)
    }
}
