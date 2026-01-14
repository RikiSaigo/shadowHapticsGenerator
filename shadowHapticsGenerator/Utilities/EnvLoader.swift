//
//  EnvLoader.swift
//  anchorMemory
//
//  Created by chiba yuto on 2025/06/17.
//

import Foundation

/// 環境変数をロードするユーティリティ
class EnvLoader {
    static func loadEnv() -> [String: String] {
        guard let path = Bundle.main.path(forResource: ".env", ofType: nil) else {
            return [:]
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }

        var env: [String: String] = [:]

        content.components(separatedBy: .newlines).forEach { line in
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") else { return }

            let parts = trimmedLine.components(separatedBy: "=")
            guard parts.count >= 2 else { return }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)

            env[key] = value
        }

        return env
    }
}
