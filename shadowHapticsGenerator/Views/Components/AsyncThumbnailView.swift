import SwiftUI
import AppKit

// MARK: - Async Thumbnail View

/// 非同期でサムネイル画像を読み込むビュー
struct AsyncThumbnailView: View {
    let url: URL
    @State private var image: NSImage? = nil
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Rectangle().fill(Color.gray.opacity(0.2))
                    ProgressView()
                }
            }
        }
        .onAppear {
            loadImageAsync()
        }
    }
    
    /// バックグラウンドスレッドで画像を読み込み、サムネイルサイズにリサイズ
    private func loadImageAsync() {
        guard image == nil else { return }
        Task.detached(priority: .userInitiated) {
            if let loadedImage = NSImage(contentsOf: url) {
                let thumbnailSize = NSSize(width: 400, height: 225)
                let resized = loadedImage.resizedAspectFill(to: thumbnailSize)
                await MainActor.run {
                    withAnimation {
                        self.image = resized ?? loadedImage
                    }
                }
            }
        }
    }
}
