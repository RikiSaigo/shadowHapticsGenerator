import SwiftUI
import AppKit

// MARK: - Sample/History Selection View

/// サンプルまたは履歴フォルダから画像ペアを選択するビュー
struct SampleSelectionView: View {
    let targetFolderName: String
    let onSelect: (URL, URL) -> Void
    let onCancel: () -> Void
    
    @EnvironmentObject var penModel: PenInputModel
    
    @State private var samples: [SamplePair] = []
    @State private var errorMessage: String? = nil
    @State private var isLoadingSamples: Bool = true
    
    // スクロール関連
    @State private var scrollOffset: CGFloat = 0.0
    @State private var contentHeight: CGFloat = 0.0
    @State private var containerHeight: CGFloat = 0.0
    @State private var lastDragLocation: CGPoint? = nil
    
    // 長押し判定用
    @State private var pressStartTime: Date? = nil
    @State private var pendingSelection: SamplePair? = nil
    @State private var longPressTask: Task<Void, Never>? = nil
    @State private var isLocalScrollMode: Bool = false
    @State private var hasPenLiftedSinceAppear: Bool = false
    
    private let longPressDuration: TimeInterval = 0.5  // 0.5秒
    
    let columns = [GridItem(.adaptive(minimum: 400), spacing: 10)]
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                PenButton(action: onCancel) {
                    HStack {
                        Image(systemName: "chevron.left")
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                Spacer()
                Text("\(targetFolderName.capitalized)").font(.headline)
                Spacer()
                Color.clear.frame(width: 50, height: 1)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .zIndex(1)
            
            // エラー表示
            if let error = errorMessage {
                Text(error).foregroundColor(.red).padding()
            }
            
            // コンテンツ
            if isLoadingSamples {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else {
                GeometryReader { geometry in
                    VStack(alignment: .leading, spacing: 0) {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(samples) { sample in
                                // 通常のViewとして表示（タップはpressure監視で処理）
                                VStack {
                                    AsyncThumbnailView(url: sample.rgbURL)
                                        .shadow(radius: 3)
                                }
                                .padding(10)
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 2)
                                .background(
                                    GeometryReader { itemGeo -> Color in
                                        let frame = itemGeo.frame(in: .named("SampleSelectionSpace"))
                                        // ペン位置がこのアイテム内にあるかチェック
                                        DispatchQueue.main.async {
                                            if let penLoc = penModel.location,
                                               frame.contains(penLoc),
                                               penModel.pressure > 0,
                                               pendingSelection == nil,
                                               !isLocalScrollMode,
                                               penModel.isSelectionEnabled {
                                                // 長押し判定開始
                                                startLongPressDetection(for: sample)
                                            }
                                        }
                                        return Color.clear
                                    }
                                )
                            }
                        }
                        .padding(10)
                        .background(
                            GeometryReader { contentGeo -> Color in
                                DispatchQueue.main.async {
                                    self.contentHeight = contentGeo.size.height
                                }
                                return Color.clear
                            }
                        )
                    }
                    .frame(width: geometry.size.width, alignment: .top)
                    .offset(y: scrollOffset)
                    .onAppear {
                        self.containerHeight = geometry.size.height
                    }
                    .onChange(of: geometry.size.height) { _, newHeight in
                        self.containerHeight = newHeight
                    }
                }
                .clipShape(Rectangle())
                .coordinateSpace(name: "SampleSelectionSpace")
            }
        }
        .padding(0)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // 画面遷移時にリセット
            penModel.resetForViewTransition()
            hasPenLiftedSinceAppear = false
            Task { await loadSamplesAsync() }
        }
        .onChange(of: penModel.pressure) { _, newPressure in
            handlePressureChange(newPressure: newPressure)
        }
        .onChange(of: penModel.location) { _, newLocation in
            handleScroll(newLocation: newLocation)
        }
    }
    
    // MARK: - Long Press Detection
    
    /// 長押し判定を開始
    private func startLongPressDetection(for sample: SamplePair) {
        guard pendingSelection == nil else { return }
        
        pendingSelection = sample
        pressStartTime = Date()
        
        longPressTask?.cancel()
        longPressTask = Task {
            // 0.5秒待機
            try? await Task.sleep(nanoseconds: UInt64(longPressDuration * 1_000_000_000))
            
            if !Task.isCancelled {
                await MainActor.run {
                    // 0.5秒経過 → スクロールモードに移行
                    isLocalScrollMode = true
                    penModel.isScrollMode = true
                    pendingSelection = nil
                }
            }
        }
    }
    
    /// 筆圧変化を処理
    private func handlePressureChange(newPressure: CGFloat) {
        if newPressure <= 0 {
            // ペンを離した
            longPressTask?.cancel()
            longPressTask = nil
            
            if let sample = pendingSelection, !isLocalScrollMode, penModel.isSelectionEnabled {
                // 0.5秒未満で離した → 選択
                onSelect(sample.rgbURL, sample.depthURL)
            }
            
            // リセット
            pendingSelection = nil
            pressStartTime = nil
            isLocalScrollMode = false
            penModel.isScrollMode = false
            lastDragLocation = nil
            
            // ペンを離したことを記録
            hasPenLiftedSinceAppear = true
        } else {
            // ペンが再度タッチした
            if hasPenLiftedSinceAppear && !penModel.isSelectionEnabled {
                penModel.isSelectionEnabled = true
            }
        }
    }
    
    /// ペンによるスクロール処理
    private func handleScroll(newLocation: CGPoint?) {
        guard isLocalScrollMode, let currentLoc = newLocation else {
            if !isLocalScrollMode {
                lastDragLocation = nil
            }
            return
        }
        
        if let lastLoc = lastDragLocation {
            let deltaY = currentLoc.y - lastLoc.y
            var newOffset = scrollOffset + deltaY
            let minOffset = min(0, containerHeight - contentHeight)
            let maxOffset: CGFloat = 0
            if newOffset > maxOffset { newOffset = maxOffset }
            if newOffset < minOffset { newOffset = minOffset }
            scrollOffset = newOffset
        }
        lastDragLocation = currentLoc
    }
    
    // MARK: - Load Samples
    
    /// サンプル画像ペアを非同期で読み込み
    private func loadSamplesAsync() async {
        isLoadingSamples = true
        errorMessage = nil
        let sourceFile = URL(fileURLWithPath: #file)
        let projectDir = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        let sampleDir = projectDir.appendingPathComponent(targetFolderName)
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sampleDir.path, isDirectory: &isDir), isDir.boolValue else {
            await MainActor.run {
                errorMessage = "\(targetFolderName)フォルダが見つかりません: \(sampleDir.path)"
                isLoadingSamples = false
            }
            return
        }
        
        let loadedSamples = await Task.detached(priority: .userInitiated) { () -> [SamplePair] in
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: sampleDir, includingPropertiesForKeys: nil)
                let rgbFiles = fileURLs.filter { $0.lastPathComponent.hasSuffix("_rgb.png") }
                var results: [SamplePair] = []
                for rgbURL in rgbFiles {
                    let filename = rgbURL.lastPathComponent
                    let prefix = filename.replacingOccurrences(of: "_rgb.png", with: "")
                    let depthFilename = "\(prefix)_depth.png"
                    let depthURL = sampleDir.appendingPathComponent(depthFilename)
                    if FileManager.default.fileExists(atPath: depthURL.path) {
                        results.append(SamplePair(rgbURL: rgbURL, depthURL: depthURL, name: prefix))
                    }
                }
                return results.sorted(by: { $0.name > $1.name })
            } catch {
                return []
            }
        }.value
        
        await MainActor.run {
            self.samples = loadedSamples
            if self.samples.isEmpty { errorMessage = "画像が見つかりませんでした" }
            self.isLoadingSamples = false
        }
    }
}
