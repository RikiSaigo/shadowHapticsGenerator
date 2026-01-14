import SwiftUI
import AppKit

// MARK: - Generation Display View

/// 画像生成中および生成結果を表示するビュー
struct GenerationDisplayView: View {
    @ObservedObject var viewModel: ImageGeneratorViewModel
    var onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            // 画像プレビュー
            HStack(spacing: 50) {
                VStack {
                    Text("Display Image")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    imagePreview(image: viewModel.image1)
                }
                
                VStack {
                    Text("Height Map Image")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    imagePreview(image: viewModel.image2)
                }
            }
            .padding(.horizontal, 50)
            
            // ステータスメッセージ
            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.headline)
                    .foregroundColor(viewModel.errorMessage != nil ? .red : .blue)
                    .padding(.top, 20)
            }
            
            // エラーメッセージ
            if let error = viewModel.errorMessage {
                ScrollView {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                        .textSelection(.enabled)
                }
                .frame(height: 80)
            }
        }
        .frame(width: screenWidth, height: screenHeight)
    }
    
    /// 画像プレビューを表示するヘルパービュー
    func imagePreview(image: NSImage?) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(16/9, contentMode: .fit)
                .frame(maxWidth: 800)
            
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity.animation(.easeInOut(duration: 1.0)))
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
    }
}
