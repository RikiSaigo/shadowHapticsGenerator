import Foundation
import SwiftUI

// MARK: - 画面サイズ設定
let screenWidth: CGFloat = 1920
let screenHeight: CGFloat = 1080

// MARK: - API設定
enum AppConfig {
    // 環境変数から読み込む、または直接設定
    static let googleApiKey: String = {
//        // 環境変数から読み込み試行
//        if let envKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"], !envKey.isEmpty {
//            return envKey
//        }
        let env = EnvLoader.loadEnv()

        if env.isEmpty {
            print("API Key が存在しません")
        }
        
        return env["GEMINI_API_KEY"] ?? ""
        // デフォルト値（開発用）- 本番では環境変数を使用してください
        //return "api_key"
    }()
    
    static let geminiEndpointUrl = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image-preview:generateContent"
    
    // APIリクエストURL生成
    static var geminiRequestUrl: URL? {
        URL(string: "\(geminiEndpointUrl)?key=\(googleApiKey)")
    }
}

// MARK: - 画像生成プロンプト設定
enum PromptConfig {
    static func displayImagePrompt(for subject: String) -> String {
        """
        \(subject)の画像を出力してください。
        作成にあたっては、以下の条件を厳守してください。
        ・\(Int(screenWidth))x\(Int(screenHeight))のサイズで出力してください。
        ・フルサイズ一眼レフで、80mmのレンズを使用した写真にしてください。
        ・ボケがなく全体にピントが合った画像にしてください。
        ・オブジェクトが面の場合、面を正面から平行にとらえた画像にし、オブジェクトが面ではない場合、そのオブジェクトを画面の中央に配置してください。
        ・オブジェクトは画面いっぱいに配置し、背景は映らないようにしてください。
        """
    }
    
    static let depthMapPrompt = """
        添付画像のheightmap画像を作成してください。
        作成にあたっては、以下の条件を厳守してください。
        ・heightmap画像とは、対象物の「高さ（隆起）」をグレースケールで表現した画像のことです。
        ・輝度の定義：「黒」は最も低い位置（基準面・底面）を表し、「白」は最も高い位置（突起部・頂点）を表すようにマッピングしてください。
        ・添付画像とheightmap画像は、ピクセルレベルで座標・形状を完全に一致させてください。
        ・heightmap画像は \(Int(screenWidth))x\(Int(screenHeight)) のサイズで出力してください。
        """
}
