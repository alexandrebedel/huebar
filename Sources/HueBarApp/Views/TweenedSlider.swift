import SwiftUI

/// Slider dont la valeur suit les changements EXTERNES (propagation du slider de pièce,
/// refresh bridge) avec une transition douce (~340 ms, smoothstep) au lieu de sauter.
/// Le drag utilisateur reste direct ; `onCommit` est appelé au relâchement.
struct TweenedSlider: View {
    let target: Double
    let range: ClosedRange<Double>
    var onCommit: (Double) -> Void
    @State private var value: Double = 0
    @State private var dragging = false
    @State private var tween: Task<Void, Never>?

    var body: some View {
        Slider(value: $value, in: range) { editing in
            dragging = editing
            if !editing {
                tween?.cancel()
                onCommit(value)
            }
        }
        .onAppear { value = target }
        .onChange(of: target) { _, newValue in
            guard !dragging else { return }
            animate(to: newValue)
        }
    }

    private func animate(to target: Double) {
        tween?.cancel()
        guard abs(target - value) > 0.5 else {
            value = target
            return
        }
        tween = Task { @MainActor in
            let start = value
            let steps = 12
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(28))
                guard !Task.isCancelled else { return }
                let t = Double(step) / Double(steps)
                value = start + (target - start) * (t * t * (3 - 2 * t))
            }
        }
    }
}
