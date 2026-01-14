import SwiftUI

// MARK: - Paint Data Models

/// ペイントの1ストローク（線）を表すモデル
struct PaintStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat
}

/// 描画基準位置の定義
enum PaintSource: String, CaseIterable {
    case shadow = "Shadow (Haptic)"
    case raw = "Raw (Physical)"
}

// MARK: - Sample Data Models

/// サンプル画像ペア（RGB画像とDepth画像）を表すモデル
struct SamplePair: Identifiable {
    let id = UUID()
    let rgbURL: URL
    let depthURL: URL
    let name: String
    
    var displayName: String {
        let components = name.components(separatedBy: "_")
        if components.count >= 2 {
            return "\(components[0])-\(components[1])"
        }
        return name
    }
}
