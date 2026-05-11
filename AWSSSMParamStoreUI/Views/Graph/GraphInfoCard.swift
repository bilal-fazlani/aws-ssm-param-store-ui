import SwiftUI

struct GraphInfoCard: View {
    let node: ConfigNode
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.fullPath)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let value = displayValue {
                    Text(value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                HStack(spacing: 10) {
                    if let type = node.type { Text(type) }
                    if let v = node.version { Text("v\(v)") }
                    if let modified = node.lastModified {
                        Text("updated \(modified.formatted(.relative(presentation: .named)))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onOpen) {
                Label("Open", systemImage: "arrow.up.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: 600)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(radius: 6, y: 2)
    }

    private var displayValue: String? {
        if node.type == "SecureString" {
            return "••••••••"
        }
        return node.value ?? node.serverValue
    }
}
