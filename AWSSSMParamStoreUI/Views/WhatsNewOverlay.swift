import SwiftUI
import Textual

struct WhatsNewOverlay: View {
    let version: String
    let releaseNotes: String
    let onDismiss: () -> Void

    private var releaseURL: URL? {
        URL(string: "https://github.com/bilal-fazlani/aws-ssm-param-store-ui/releases/tag/v\(version)")
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.25).ignoresSafeArea())

            VStack(spacing: 0) {
                // Title area
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What's New")
                            .font(.title2.weight(.semibold))

                        Text("Version \(version)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Spacer()
                }
                .padding(.horizontal, 48)
                .padding(.top, 52)
                .padding(.bottom, 16)

                Divider()
                    .padding(.horizontal, 48)

                // Scrollable release notes
                ScrollView {
                    StructuredText(markdown: releaseNotes)
                        .textual.structuredTextStyle(.gitHub)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                    .padding(.horizontal, 48)

                // Footer
                HStack(spacing: 16) {
                    keyHint("esc", label: "dismiss")

                    Spacer()

                    if let url = releaseURL {
                        Link("View on GitHub", destination: url)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button("Continue") { onDismiss() }
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 20)
            }
            .frame(maxWidth: 640, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Button("") { onDismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
        }
    }

    @ViewBuilder
    private func keyHint(_ key: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
