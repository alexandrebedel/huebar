import AppKit
import SwiftUI

/// Éditeur de thème custom : un nom + quatre couleurs dont on ne garde que la
/// teinte — elles deviennent les ancres du mapper, comme les thèmes intégrés.
struct ThemeEditorView: View {
    let isNew: Bool
    let onSave: (CustomTheme) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var theme: CustomTheme
    @State private var colors: [Color]

    init(theme: CustomTheme, isNew: Bool, onSave: @escaping (CustomTheme) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _theme = State(initialValue: theme)
        _colors = State(initialValue: theme.anchors.map {
            Color(hue: $0, saturation: 0.85, brightness: 1)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Nouveau thème" : "Modifier le thème")
                .font(.headline)
            TextField("Nom du thème", text: $theme.name)
            HStack(spacing: 10) {
                ForEach(colors.indices, id: \.self) { index in
                    ColorPicker("", selection: $colors[index], supportsOpacity: false)
                        .labelsHidden()
                }
                Spacer()
            }
            Text("Seule la teinte compte : ces couleurs deviennent les ancres de la sync.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Enregistrer") {
                    var saved = theme
                    saved.name = theme.name.trimmingCharacters(in: .whitespaces)
                    saved.anchors = colors.map(Self.hue(of:))
                    onSave(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(theme.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private static func hue(of color: Color) -> Double {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
        return Double(rgb.hueComponent)
    }
}
