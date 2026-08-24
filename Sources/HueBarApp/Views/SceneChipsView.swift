import SwiftUI
import HueKit

struct SceneChipsView: View {
    let title: String?
    let scenes: [HueScene]
    let state: HueState

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.headline)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(scenes) { scene in
                    Button {
                        Task { await state.recallScene(id: scene.id) }
                    } label: {
                        Text(scene.metadata.name)
                            .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
