import SwiftUI

// MARK: - Custom Pen Button

/// ペンの筆圧に対応したカスタムボタンコンポーネント
struct PenButton<Label: View>: View {
    let action: () -> Void
    let label: Label
    
    @EnvironmentObject var penModel: PenInputModel
    @State private var hasTriggered = false
    @State private var buttonFrame: CGRect = .zero
    
    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }
    
    var body: some View {
        Button(action: action) {
            label
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        self.buttonFrame = geo.frame(in: .named("WindowSpace"))
                    }
                    .onChange(of: geo.frame(in: .named("WindowSpace"))) { _, newFrame in
                        self.buttonFrame = newFrame
                    }
            }
        )
        .onChange(of: penModel.pressure) { _, newPressure in
            guard let penLoc = penModel.location else { return }
            let pressThreshold: CGFloat = 0.05
            
            if buttonFrame.contains(penLoc) {
                if newPressure > pressThreshold {
                    if !hasTriggered {
                        action()
                        hasTriggered = true
                    }
                } else if newPressure == 0 {
                    hasTriggered = false
                }
            } else {
                hasTriggered = false
            }
        }
    }
}
