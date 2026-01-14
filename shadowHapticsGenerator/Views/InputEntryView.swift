import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Input Entry View

/// プロンプト入力と画像アップロードの初期画面
struct InputEntryView: View {
    @ObservedObject var viewModel: ImageGeneratorViewModel
    var onEnter: () -> Void
    var onSampleTapped: () -> Void
    var onHistoryTapped: () -> Void
    var onImageUploaded: () -> Void
    
    @FocusState private var isInputFocused: Bool
    
    // UI定数
    private let buttonWidth: CGFloat = 160
    private let buttonHeight: CGFloat = 50
    private let boxWidth: CGFloat = 600
    private let boxHeight: CGFloat = 150
    
    private let placeholderText = ""
    
    /// テキスト長に応じた動的フォントサイズ
    private var dynamicFontSize: CGFloat {
        let text = viewModel.prompt.isEmpty ? "Sample Text" : viewModel.prompt
        let weightedLength = text.reduce(0.0) { $0 + ($1.isASCII ? 0.6 : 1.0) }
        var bestSize: CGFloat = 10.0
        
        for lines in 1...5 {
            let linesFloat = CGFloat(lines)
            let heightLimit = (boxHeight / linesFloat) * 0.85
            let charsPerLine = max(1.0, weightedLength / linesFloat)
            let widthLimit = (boxWidth / charsPerLine) * 0.95
            
            let possibleSize = min(heightLimit, widthLimit)
            
            if possibleSize > bestSize {
                bestSize = possibleSize
            }
        }
        return min(bestSize, 130)
    }
    
    var body: some View {
        VStack {
            Spacer()
            
            // メイン入力エリア
            HStack(alignment: .center, spacing: 20) {
                ZStack(alignment: .center) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: boxWidth, height: boxHeight)
                        .onTapGesture {
                            isInputFocused = true
                        }
                    
                    TextField(placeholderText, text: $viewModel.prompt, axis: .vertical)
                        .focused($isInputFocused)
                        .textFieldStyle(.plain)
                        .font(.system(size: dynamicFontSize, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .frame(width: boxWidth, alignment: .center)
                        .foregroundColor(.primary)
                        .onSubmit {
                            if !viewModel.prompt.isEmpty {
                                onEnter()
                            }
                        }
                        .animation(.easeInOut(duration: 0.1), value: dynamicFontSize)
                }
                
                Text("を触る")
                    .font(.system(size: 100, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // ボタン群
            HStack(spacing: 40) {
                PenButton(action: openFilePanel) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Image Upload")
                    }
                    .font(.headline)
                    .frame(width: buttonWidth, height: buttonHeight)
                    .background(Color.orange)
                    .foregroundColor(.white)
                }
                
                PenButton(action: onHistoryTapped) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("History")
                    }
                    .font(.headline)
                    .frame(width: buttonWidth, height: buttonHeight)
                    .background(Color.gray)
                    .foregroundColor(.white)
                }
                
                PenButton(action: onSampleTapped) {
                    HStack {
                        Image(systemName: "photo.stack")
                        Text("Sample")
                    }
                    .font(.headline)
                    .frame(width: buttonWidth, height: buttonHeight)
                    .background(Color.gray)
                    .foregroundColor(.white)
                }
            }
            .padding(.bottom, 60)
        }
        .frame(width: screenWidth, height: screenHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isInputFocused = true
        }
    }
    
    /// ファイル選択パネルを開く
    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.prompt = "Import Image"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let accessStart = url.startAccessingSecurityScopedResource()
                guard let loadedImage = NSImage(contentsOf: url) else {
                    if accessStart { url.stopAccessingSecurityScopedResource() }
                    return
                }
                if accessStart { url.stopAccessingSecurityScopedResource() }
                
                viewModel.processUploadedImage(image: loadedImage)
                onImageUploaded()
            }
        }
    }
}
