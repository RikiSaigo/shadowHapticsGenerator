import SwiftUI

// MARK: - Custom Cursor View (カスタムカーソル)

/// ペンの位置に表示するカスタムカーソルビュー
struct CustomCursorView: View {
    @EnvironmentObject var penModel: PenInputModel
    
    private let cursorSize: CGFloat = 20
    
    var body: some View {
        if let location = penModel.uiLocation {
            Circle()
                .fill(getCursorColor())
                .frame(width: cursorSize, height: cursorSize)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .position(x: location.x, y: location.y)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.1), value: penModel.pressure)
                .animation(.easeInOut(duration: 0.2), value: penModel.isScrollMode)
        }
    }
    
    /// 現在の状態に応じたカーソル色を返す
    private func getCursorColor() -> Color {
        if penModel.isScrollMode {
            return Color.orange
        } else if penModel.pressure > 0 {
            return Color.blue
        } else {
            return Color.gray.opacity(0.5)
        }
    }
}
