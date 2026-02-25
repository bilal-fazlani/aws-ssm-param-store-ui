import SwiftUI

// MARK: - Semantic Colors

extension Color {
    static let panelBackground = Color(nsColor: .windowBackgroundColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let accentTint = Color.accentColor.opacity(0.15)
    
    // Type-based colors for SSM parameter types
    static func parameterTypeColor(for type: String?) -> Color {
        switch type {
        case "SecureString": return .red
        case "StringList": return .purple
        case "String": return .blue
        default: return .secondary
        }
    }
}

// MARK: - Layered Glass Pane

struct GlassPane: ViewModifier {
    var material: Material = .ultraThin
    var cornerRadius: CGFloat = 12
    var enableDepth: Bool = true
    
    func body(content: Content) -> some View {
        content
            .background {
                if enableDepth {
                    // Outer glow layer
                    RoundedRectangle(cornerRadius: cornerRadius + 2)
                        .fill(material.opacity(0.3))
                        .blur(radius: 1)
                        .offset(y: 1)
                }
            }
            .background(material)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Glass Button Style

struct GlassButtonStyle: ButtonStyle {
    var color: Color = .blue
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                color.opacity(configuration.isPressed ? 0.25 : 0.12)
            )
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        LinearGradient(
                            colors: [color.opacity(0.4), color.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: color.opacity(configuration.isPressed ? 0.3 : 0.15), radius: configuration.isPressed ? 2 : 6, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .foregroundStyle(color)
            .fontWeight(.semibold)
    }
}

// MARK: - Modern Badge

struct ModernBadge: View {
    let text: String
    var color: Color = .blue
    
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                    )
            )
            .foregroundStyle(color)
    }
}

// MARK: - Shimmer Loading View

struct ShimmerView: View {
    @State private var phase: CGFloat = -200
    var height: CGFloat = 20
    var cornerRadius: CGFloat = 6
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.15))
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.4),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 100)
                    .offset(x: phase)
                    .onAppear {
                        withAnimation(
                            .linear(duration: 1.2)
                            .repeatForever(autoreverses: false)
                        ) {
                            phase = geo.size.width + 100
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .frame(height: height)
    }
}

struct ShimmerListItem: View {
    /// Alternates between folder-like and parameter-like rows to better match
    /// the real sidebar content (folders have a count badge; params have a type badge).
    var isFolder: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            // Icon badge — matches the 24×24 size used in FolderRow and ParameterRow
            ShimmerView(height: 24, cornerRadius: 6)
                .frame(width: 24)
            // Name — folders tend to have shorter names
            ShimmerView(height: 13, cornerRadius: 4)
                .frame(maxWidth: isFolder ? 100 : .infinity)
            Spacer(minLength: 0)
            // Right badge — count capsule for folders, type badge for params
            ShimmerView(height: 13, cornerRadius: isFolder ? 7 : 4)
                .frame(width: isFolder ? 22 : 26)
        }
        .padding(.vertical, isFolder ? 2 : 3)
    }
}

// MARK: - Hoverable Row Style

struct HoverableRowStyle: ViewModifier {
    @State private var isHovered = false
    var accentColor: Color = .accentColor
    
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? accentColor.opacity(0.1) : .clear)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    var message: String = "Loading..."
    
    var body: some View {
        ZStack {
            // Frosted glass background
            Rectangle()
                .fill(.ultraThinMaterial)
            
            // Centered spinner and text
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.secondary)
                
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
            }
        }
    }
}

struct LoadingOverlayModifier: ViewModifier {
    let isLoading: Bool
    var message: String = "Loading..."
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if isLoading {
                    LoadingOverlay(message: message)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

// MARK: - Extensions

extension View {
    func glassPane(material: Material = .ultraThin, cornerRadius: CGFloat = 12, enableDepth: Bool = true) -> some View {
        self.modifier(GlassPane(material: material, cornerRadius: cornerRadius, enableDepth: enableDepth))
    }
    
    func hoverableRow(accentColor: Color = .accentColor) -> some View {
        self.modifier(HoverableRowStyle(accentColor: accentColor))
    }
    
    func loadingOverlay(isLoading: Bool, message: String = "Loading...") -> some View {
        self.modifier(LoadingOverlayModifier(isLoading: isLoading, message: message))
    }
}
