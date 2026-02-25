import SwiftUI

// MARK: - Connection Picker Overlay

struct ConnectionPickerOverlay: View {
    @ObservedObject var connectionStore: ConnectionStore
    var onConnect: (Connection) -> Void
    var onManage: () -> Void

    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    private var connections: [Connection] {
        connectionStore.connections
    }

    var body: some View {
        ZStack {
            // ── Liquid Glass background ──
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.25).ignoresSafeArea())

            // ── Hidden text field for keyboard capture ──
            TextField("", text: .constant(""))
                .focused($isFocused)
                .frame(width: 0, height: 0)
                .opacity(0)
                .onKeyPress(.upArrow) {
                    if selectedIndex > 0 { selectedIndex -= 1 }
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    if selectedIndex < connections.count - 1 { selectedIndex += 1 }
                    return .handled
                }
                .onKeyPress(.return) {
                    guard !connections.isEmpty, selectedIndex < connections.count else { return .ignored }
                    onConnect(connections[selectedIndex])
                    return .handled
                }

            // ── Main content ──
            VStack(spacing: 0) {
                Spacer()

                // Header
                VStack(spacing: 14) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 56, weight: .ultraLight))
                        .foregroundStyle(.tertiary)

                    VStack(spacing: 8) {
                        Text("Select a Connection")
                            .font(.largeTitle.weight(.semibold))

                        Text(connections.isEmpty
                             ? "Add a connection to get started with AWS SSM Parameter Store"
                             : "Choose an environment to browse")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                    }
                }

                Spacer().frame(height: 44)

                if connections.isEmpty {
                    // Empty state — single prominent action
                    Button {
                        onManage()
                    } label: {
                        Label("Add Connection", systemImage: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    // Connection cards
                    VStack(spacing: 8) {
                        ForEach(Array(connections.enumerated()), id: \.element.id) { index, connection in
                            ConnectionCard(
                                connection: connection,
                                isSelected: index == selectedIndex
                            ) {
                                onConnect(connection)
                            }
                            .onHover { hovering in
                                if hovering { selectedIndex = index }
                            }
                        }
                    }
                    .frame(width: 500)

                    Spacer().frame(height: 28)

                    // Manage connections
                    Button {
                        onManage()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gear")
                                .font(.caption.weight(.medium))
                            Text("Manage Connections")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(",", modifiers: [.command])
                }

                Spacer()
            }
            .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            selectedIndex = 0
            DispatchQueue.main.async { isFocused = true }
        }
    }
}

// MARK: - Connection Card

struct ConnectionCard: View {
    let connection: Connection
    let isSelected: Bool
    let onTap: () -> Void

    private var typeColor: Color {
        switch connection.type {
        case .localstack:   return .green
        case .ssoProfile:   return .blue
        case .credentials:  return .orange
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Colored icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(typeColor.gradient)
                        .frame(width: 46, height: 46)
                    Image(systemName: connection.type.icon)
                        .foregroundStyle(.white)
                        .font(.system(size: 20, weight: .medium))
                }

                // Name + detail
                VStack(alignment: .leading, spacing: 3) {
                    Text(connection.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(connection.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Region badge
                Text(connection.region)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(16)
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}
