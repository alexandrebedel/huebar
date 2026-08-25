import SwiftUI

extension View {
    /// Alerte de renommage partagée (lampe, pièce, scène) : champ texte + validation,
    /// le nom vide est ignoré.
    func renameAlert(
        _ title: String, isPresented: Binding<Bool>, name: Binding<String>,
        onSubmit: @escaping (String) -> Void
    ) -> some View {
        alert(title, isPresented: isPresented) {
            TextField("Nom", text: name)
            Button("Renommer") {
                let trimmed = name.wrappedValue.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { onSubmit(trimmed) }
            }
            Button("Annuler", role: .cancel) {}
        }
    }
}
