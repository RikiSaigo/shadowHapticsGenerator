import Foundation

// MARK: - Polynomial Regression Model (2次多項式回帰モデル)

/// 2次多項式回帰モデル: y = ax² + bx + c
struct PolynomialRegressionModel {
    let a: Double
    let b: Double
    let c: Double
    
    /// 与えられたxに対する予測値を返す
    func predict(x: Double) -> Double {
        return a * x * x + b * x + c
    }
    
    /// 最小二乗法によりデータから回帰モデルを生成
    /// - Parameters:
    ///   - xValues: 説明変数の配列
    ///   - yValues: 目的変数の配列
    /// - Returns: フィッティングされた回帰モデル。データが不足している場合はnil
    static func fit(xValues: [Double], yValues: [Double]) -> PolynomialRegressionModel? {
        guard xValues.count == yValues.count, xValues.count >= 3 else { return nil }
        let n = Double(xValues.count)
        
        // 各次数の和を計算
        let sumX = xValues.reduce(0, +)
        let sumX2 = xValues.reduce(0) { $0 + $1 * $1 }
        let sumX3 = xValues.reduce(0) { $0 + $1 * $1 * $1 }
        let sumX4 = xValues.reduce(0) { $0 + $1 * $1 * $1 * $1 }
        
        let sumY = yValues.reduce(0, +)
        let sumXY = zip(xValues, yValues).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2Y = zip(xValues, yValues).reduce(0) { $0 + $1.0 * $1.0 * $1.1 }
        
        // 拡大係数行列を構築
        var mat = [
            [n, sumX, sumX2, sumY],
            [sumX, sumX2, sumX3, sumXY],
            [sumX2, sumX3, sumX4, sumX2Y]
        ]
        
        // ガウスの消去法で解を求める
        for i in 0..<3 {
            let pivot = mat[i][i]
            if abs(pivot) < 1e-9 { return nil }
            
            for j in i..<4 {
                mat[i][j] /= pivot
            }
            
            for k in 0..<3 {
                if k != i {
                    let factor = mat[k][i]
                    for j in i..<4 {
                        mat[k][j] -= factor * mat[i][j]
                    }
                }
            }
        }
        
        let c_val = mat[0][3]
        let b_val = mat[1][3]
        let a_val = mat[2][3]
        
        return PolynomialRegressionModel(a: a_val, b: b_val, c: c_val)
    }
}
