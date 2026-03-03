import SwiftUI

/// A list editor for AWS SSM StringList parameters. Binds to a comma-separated string
/// and provides add/remove/edit UI for individual items.
struct StringListEditor: View {
    @Binding var commaSeparatedValue: String

    private struct ListItem: Identifiable, Equatable {
        let id: UUID
        var value: String

        init(id: UUID = UUID(), value: String) {
            self.id = id
            self.value = value
        }
    }

    @State private var items: [ListItem] = []

    private static func parse(_ s: String) -> [ListItem] {
        guard !s.isEmpty else { return [] }
        return s.components(separatedBy: ",")
            .map { ListItem(value: $0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func serialize(_ items: [ListItem]) -> String {
        items.map { $0.value.trimmingCharacters(in: .whitespaces) }
             .filter { !$0.isEmpty }
             .joined(separator: ",")
    }

    private func syncFromBinding() {
        items = Self.parse(commaSeparatedValue)
        if items.isEmpty {
            items = [ListItem(value: "")]
        }
    }

    private func syncToBinding() {
        commaSeparatedValue = Self.serialize(items)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, _ in
                    HStack(alignment: .center, spacing: 8) {
                        TextField("item text..", text: $items[index].value)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.separator, lineWidth: 0.5)
                            )
                            .focusEffectDisabled()
                            .onChange(of: items[index].value) { _, _ in
                                syncToBinding()
                            }

                        Button {
                            items.remove(at: index)
                            syncToBinding()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }

            Button {
                items.append(ListItem(value: ""))
                syncToBinding()
            } label: {
                Label("Add Item", systemImage: "plus.circle")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
        }
        .onAppear {
            syncFromBinding()
        }
        .onChange(of: commaSeparatedValue) { _, newValue in
            let currentSerialized = Self.serialize(items)
            if currentSerialized != newValue {
                syncFromBinding()
            }
        }
    }
}
