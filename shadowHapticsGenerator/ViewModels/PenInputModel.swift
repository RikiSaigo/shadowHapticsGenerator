import SwiftUI
import Combine

// MARK: - Shared Pen Input Model (ペン入力を共有管理)

/// ペン（スタイラス）の入力状態を管理するObservableObjectクラス
class PenInputModel: ObservableObject {
    /// ペンの現在位置（画面座標）
    @Published var location: CGPoint? = nil
    
    /// ペンの筆圧 (0.0 〜 1.0)
    @Published var pressure: CGFloat = 0.0
    
    /// ペンの傾き (x, y)
    @Published var tilt: NSPoint = .zero
    
    /// スクロールモードかどうか（長押しで有効化）
    @Published var isScrollMode: Bool = false
    
    /// 選択が有効かどうか（画面遷移直後はfalse、ペンを離して再タッチでtrue）
    @Published var isSelectionEnabled: Bool = true
    
    /// 画面遷移時にステートをリセット
    func resetForViewTransition() {
        isSelectionEnabled = false
        isScrollMode = false
    }
    
    /// UI表示用の位置（将来的な変換処理用）
    var uiLocation: CGPoint? {
        guard let loc = location else { return nil }
        return loc
    }
}
