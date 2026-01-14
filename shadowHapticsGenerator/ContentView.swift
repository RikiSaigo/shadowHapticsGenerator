import SwiftUI
import AppKit
import Combine

// MARK: - Root View

/// アプリケーションのルートビュー
/// 各画面へのルーティングとペン入力の管理を担当
struct ContentView: View {
    @StateObject private var viewModel = ImageGeneratorViewModel()
    @StateObject private var penModel = PenInputModel()
    
    @State private var navigateToDrawing = false
    @State private var showSampleSelection = false
    @State private var showHistorySelection = false
    
    @State private var longPressTask: Task<Void, Never>? = nil
    
    var body: some View {
        ZStack {
            Group {
                if navigateToDrawing,
                   let path1 = viewModel.savedImage1Path,
                   let path2 = viewModel.savedDepthMapPath {
                    
                    // 描画モード
                    PenShadowView(
                        displayImgPath: path1.path,
                        depthMapPath: path2.path,
                        viewModel: viewModel,
                        onBack: {
                            withAnimation {
                                navigateToDrawing = false
                                viewModel.reset()
                            }
                        }
                    )
                    .transition(.opacity)
                    
                } else {
                    ZStack {
                        if showSampleSelection {
                            // サンプル選択画面
                            SampleSelectionView(
                                targetFolderName: "sample",
                                onSelect: { rgbUrl, depthUrl in
                                    guard !penModel.isScrollMode else { return }
                                    viewModel.savedImage1Path = rgbUrl
                                    viewModel.savedDepthMapPath = depthUrl
                                    withAnimation {
                                        showSampleSelection = false
                                        navigateToDrawing = true
                                    }
                                },
                                onCancel: {
                                    withAnimation {
                                        showSampleSelection = false
                                    }
                                }
                            )
                            .transition(.move(edge: .bottom))
                            
                        } else if showHistorySelection {
                            // 履歴選択画面
                            SampleSelectionView(
                                targetFolderName: "history",
                                onSelect: { rgbUrl, depthUrl in
                                    guard !penModel.isScrollMode else { return }
                                    viewModel.savedImage1Path = rgbUrl
                                    viewModel.savedDepthMapPath = depthUrl
                                    withAnimation {
                                        showHistorySelection = false
                                        navigateToDrawing = true
                                    }
                                },
                                onCancel: {
                                    withAnimation {
                                        showHistorySelection = false
                                    }
                                }
                            )
                            .transition(.move(edge: .bottom))
                            
                        } else {
                            if viewModel.isGeneratingOrResult {
                                // 生成中表示
                                GenerationDisplayView(
                                    viewModel: viewModel,
                                    onComplete: {
                                        withAnimation {
                                            navigateToDrawing = true
                                        }
                                    }
                                )
                            } else {
                                // 入力画面
                                InputEntryView(
                                    viewModel: viewModel,
                                    onEnter: {
                                        withAnimation {
                                            viewModel.startGenerationState()
                                        }
                                        Task {
                                            await viewModel.generateProcess()
                                            if viewModel.isProcessComplete {
                                                withAnimation {
                                                    navigateToDrawing = true
                                                }
                                            }
                                        }
                                    },
                                    onSampleTapped: {
                                        withAnimation { showSampleSelection = true }
                                    },
                                    onHistoryTapped: {
                                        withAnimation { showHistorySelection = true }
                                    },
                                    onImageUploaded: {
                                        // viewModelの状態変化で自動遷移
                                    }
                                )
                            }
                        }
                    }
                    CustomCursorView()
                }
            }
            .environmentObject(penModel)
            
            // ペン入力ハンドラ
            PenInputView(model: penModel, shouldHideSystemCursor: true)
                .allowsHitTesting(false)
        }
        .frame(minWidth: 900, minHeight: 700)
        .edgesIgnoringSafeArea(.all)
        .coordinateSpace(name: "WindowSpace")
        .onChange(of: penModel.pressure) { _, pressure in
            handlePressureChange(pressure: pressure)
        }
        .onChange(of: viewModel.isProcessComplete) { _, complete in
            if complete && viewModel.isGeneratingOrResult {
                withAnimation {
                    navigateToDrawing = true
                }
            }
        }
    }
    
    /// 筆圧変化を処理（長押しでスクロールモード）
    private func handlePressureChange(pressure: CGFloat) {
        if navigateToDrawing { return }
        
        if pressure > 0 {
            if longPressTask == nil {
                longPressTask = Task {
                    try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
                    if !Task.isCancelled {
                        await MainActor.run {
                            penModel.isScrollMode = true
                        }
                    }
                }
            }
        } else {
            longPressTask?.cancel()
            longPressTask = nil
            penModel.isScrollMode = false
        }
    }
}

#Preview {
    ContentView()
}
