import Foundation

// MARK: - Gemini API Response Models

/// Gemini APIのレスポンス構造
struct GeminiResponse: Codable {
    let candidates: [Candidate]?
    let error: ApiError?
}

/// 生成候補
struct Candidate: Codable {
    let content: Content?
}

/// コンテンツ
struct Content: Codable {
    let parts: [Part]
}

/// パート（テキストまたは画像）
struct Part: Codable {
    let text: String?
    let inlineData: InlineData?
}

/// インラインデータ（Base64エンコードされた画像）
struct InlineData: Codable {
    let data: String
}

/// APIエラー
struct ApiError: Codable {
    let code: Int
    let message: String
}
