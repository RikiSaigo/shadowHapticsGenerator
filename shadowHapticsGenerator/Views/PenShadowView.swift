import SwiftUI
import AppKit

// MARK: - PenShadowView (描画モード)

/// ペン入力による影描画とハプティクスフィードバックを提供するメインビュー
struct PenShadowView: View {
    @EnvironmentObject var penModel: PenInputModel
    
    let displayImgPath: String
    let depthMapPath: String
    let viewModel: ImageGeneratorViewModel
    var onBack: () -> Void
    
    // MARK: - UI Settings
    @State private var showUI: Bool = false
    @State private var imageBlend: Double = 0.0
    @State private var penShadowTransparencyVal: Double = 0.80
    @State private var penShadowDeltaPixcelVal: CGFloat = 5.0
    @State private var cdDeltaThreshold: CGFloat = 10.0
    
    // 画像分析用
    @State private var depthStdDev: Double = 0.0
    @State private var roughnessIndex: Double = 0.0
    
    // 明るさ分析用
    @State private var brightnessMean: Double = 0.0
    @State private var brightnessMedian: Double = 0.0
    @State private var brightnessIndex: Double = 0.0
    
    // Index Range 円表示フラグ
    @State private var showStdRangeCircle: Bool = false
    
    // MARK: - ペイント関連
    @State private var isPaintMode: Bool = false
    @State private var paintColor: Color = .black
    @State private var paintedPaths: [PaintStroke] = []
    @State private var isDrawingStroke: Bool = false
    @State private var paintSource: PaintSource = .shadow
    @State private var currentLineWidth: CGFloat = 3.0
    
    // MARK: - 影描画関連
    @State private var penShadowShape: [CGFloat] = []
    private let pen_lib_posX: CGFloat = 0
    private let pen_lib_posY: CGFloat = 0
    private let penShadowCellSize: CGFloat = 2.0
    private let offsetX: CGFloat = 0
    private let offsetY: CGFloat = 0
    
    @State private var depthMapArray: [[Int]] = []
    @State private var hasLoaded: Bool = false
    @State private var stabilizedPenTheta: CGFloat = 0.0
    @State private var stabilizedPenAngle: CGFloat = 0.0
    @State private var stabilizedPenMovementAngle: CGFloat = 0.0
    
    @State private var previousPenLocation: CGPoint? = nil
    @State private var penMovementAngleRaw: CGFloat = 0.0
    
    // MARK: - Shadow State
    enum ShadowState {
        case idle       // 通常
        case resistance // 抵抗（CD=-0.3）
        case accelerate // 加速（CD=2.0）
    }
    @State private var shadowState: ShadowState = .idle
    @State private var animationStartTime: Date? = nil
    @State private var currentShadowLocation: CGPoint = .zero
    
    // MARK: - Cursor Shape Settings
    enum CursorShapeType: String, CaseIterable, Identifiable {
        case penShape = "Pen Shape"
        case cursor = "Cursor"
        
        var filename: String {
            switch self {
            case .penShape: return "penShape"
            case .cursor: return "cursor"
            }
        }
        
        var id: String { self.rawValue }
    }
    
    @State private var selectedCursorShape: CursorShapeType = .penShape
    
    // カラーパレット
    let paletteColors: [Color] = [.black, .red, .blue, .green, .yellow, .orange, .purple, .white]
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // 背景 & ペイント & 影描画
            ZStack {
                // 1. 背景画像
                ZStack {
                    if let bgImage1 = NSImage(contentsOf: URL(fileURLWithPath: displayImgPath)) {
                        Image(nsImage: bgImage1).resizable().scaledToFill()
                    }
                    if let bgImage2 = NSImage(contentsOf: URL(fileURLWithPath: depthMapPath)) {
                        Image(nsImage: bgImage2).resizable().scaledToFill().opacity(imageBlend)
                    }
                }
                .background(Color.gray)
                
                // 2. ペイントレイヤー
                if isPaintMode {
                    Canvas { context, size in
                        for stroke in paintedPaths {
                            var path = Path()
                            if let first = stroke.points.first {
                                path.move(to: first)
                                for point in stroke.points.dropFirst() {
                                    path.addLine(to: point)
                                }
                            }
                            context.stroke(path, with: .color(stroke.color), lineWidth: stroke.lineWidth)
                        }
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
                
                // 3. 影描画
                Canvas { context, size in
                    if penModel.location != nil {
                        drawShadows(context: &context, canvasSize: size, penLocation: currentShadowLocation, tilt: penModel.tilt)
                    }
                }
            }
            .onChange(of: penModel.location) { _, newLoc in
                updatePenDynamics(newLocation: newLoc, tilt: penModel.tilt)
            }
            .onChange(of: penModel.pressure) { _, newPressure in
                if newPressure <= 0 {
                    isDrawingStroke = false
                }
            }
            
            // Index Range表示
            if showStdRangeCircle {
                Circle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 3)
                    .frame(width: screenHeight * 0.4, height: screenHeight * 0.4)
                    .position(x: screenWidth / 2, y: screenHeight / 2)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            
            // UI Overlay
            VStack(alignment: .leading) {
                // ツールバー
                HStack(alignment: .top, spacing: 10) {
                    PenButton(action: onBack) {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .shadow(radius: 3)
                            .padding(10)
                    }
                    
                    PenButton(action: {
                        withAnimation { isPaintMode.toggle() }
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(isPaintMode ? .orange : .white)
                            .shadow(radius: 3)
                            .padding(10)
                    }
                    
                    // ペイントツール
                    if isPaintMode {
                        paintToolbar
                    }
                }
                .padding(.top, 20)
                .padding(.leading, 10)
                
                Spacer()
                
                // Settings パネル
                if showUI {
                    settingsPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            
            // キーボードショートカット
            Button("Toggle UI") { withAnimation { showUI.toggle() } }
                .keyboardShortcut("p", modifiers: [])
                .opacity(0)
        }
        .frame(width: screenWidth, height: screenHeight)
        .edgesIgnoringSafeArea(.all)
        .background(Color.white)
        .onAppear {
            guard !hasLoaded else { return }
            setup()
            hasLoaded = true
        }
        .onChange(of: selectedCursorShape) { _, newValue in
            penShadowShape = loadPenShapeFromCSV(filename: newValue.rawValue == "Pen Shape" ? "penShape" : "cursor")
        }
    }
    
    // MARK: - Subviews
    
    /// ペイントツールバー
    private var paintToolbar: some View {
        HStack(spacing: 8) {
            // カラーパレット
            ForEach(paletteColors, id: \.self) { color in
                PenButton(action: { paintColor = color }) {
                    Circle()
                        .fill(color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: paintColor == color ? 3 : 1)
                        )
                }
            }
            
            Divider().frame(height: 30)
            
            // 線の太さ変更
            VStack(spacing: 2) {
                Text("\(Int(currentLineWidth))px").font(.caption2).foregroundColor(.black)
                Slider(value: $currentLineWidth, in: 1.0...20.0)
                    .frame(width: 100)
                    .tint(.black)
            }
            .padding(.horizontal, 8)
            
            Divider().frame(height: 30)
            
            // 保存ボタン
            PenButton(action: { savePaintedImage() }) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(8)
            }
            
            // クリアボタン
            PenButton(action: { paintedPaths.removeAll() }) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .transition(.move(edge: .leading).combined(with: .opacity))
    }
    
    /// 設定パネル
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Settings").font(.headline).foregroundColor(.white)
            
            // ペイント基準位置
            VStack(alignment: .leading) {
                Text("Paint Source").font(.caption).foregroundColor(.white)
                Picker("Paint Source", selection: $paintSource) {
                    ForEach(PaintSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            
            // Cursor Shape Selection
            VStack(alignment: .leading) {
                Text("Cursor Shape").font(.caption).foregroundColor(.white)
                Picker("Cursor Shape", selection: $selectedCursorShape) {
                    ForEach(CursorShapeType.allCases) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            
            Divider().background(Color.white)
            
            VStack(alignment: .leading) {
                Text("Image Blend: \(String(format: "%.1f", imageBlend))").font(.caption).foregroundColor(.white)
                Slider(value: $imageBlend, in: 0.0...1.0).tint(.white)
            }
            VStack(alignment: .leading) {
                Text("Shadow Transparency: \(String(format: "%.2f", penShadowTransparencyVal))").font(.caption).foregroundColor(.white)
                Slider(value: $penShadowTransparencyVal, in: 0.0...1.0).tint(.white)
            }
            VStack(alignment: .leading) {
                Text("Delta Pixel (Strength): \(String(format: "%.1f", penShadowDeltaPixcelVal))").font(.caption).foregroundColor(.white)
                Slider(value: $penShadowDeltaPixcelVal, in: 0.0...30.0).tint(.white)
            }
            VStack(alignment: .leading) {
                Text("CD Threshold: \(String(format: "%.1f", cdDeltaThreshold))").font(.caption).foregroundColor(.white)
                Slider(value: $cdDeltaThreshold, in: 0.0...100.0).tint(.white)
            }
            
            VStack(alignment: .leading) {
                Text("Roughness Index: \(String(format: "%.3f", roughnessIndex))").font(.caption).foregroundColor(.white)
                Text("Brightness Index: \(String(format: "%.3f", brightnessIndex))").font(.caption).foregroundColor(.white)
                
                PenButton(action: {
                    Task {
                        withAnimation { showStdRangeCircle = true }
                        try? await Task.sleep(nanoseconds: 1_000_000)
                        withAnimation { showStdRangeCircle = false }
                    }
                }) {
                    Text("Index Range")
                        .font(.caption)
                        .padding(5)
                        .background(Color.white.opacity(0.2))
                        .foregroundColor(.white)
                        .cornerRadius(5)
                }
                .padding(.top, 5)
                
                PenButton(action: { saveHapticsLog() }) {
                    Text("Good Haptics")
                        .font(.caption)
                        .padding(5)
                        .background(Color.blue.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(5)
                }
            }
            
            Divider().background(Color.white)
            Text("Press 'P' to Hide").font(.caption2).foregroundColor(.gray)
        }
        .padding()
        .frame(width: 250)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(15)
    }
    
    // MARK: - Setup
    
    private func setup() {
        penShadowShape = loadPenShapeFromCSV(filename: selectedCursorShape.filename)
        if let depthMap = processDepthMap(imagePath: depthMapPath) {
            self.depthMapArray = depthMap
            let stdDev = calculateCircleStdDev(map: depthMap)
            self.depthStdDev = stdDev
            
            calculateImageBrightnessStats(imagePath: displayImgPath)
            
            let maxStdDev = 255.0 / 2.0
            let index = stdDev / maxStdDev
            let clampedIndex = max(0.0, min(1.0, index))
            self.roughnessIndex = clampedIndex
            
            if let deltaModel = viewModel.deltaPixelModel {
                let predictedDelta = deltaModel.predict(x: self.roughnessIndex)
                self.penShadowDeltaPixcelVal = CGFloat(max(0.0, min(30.0, predictedDelta)))
                print("Applied Delta Pixel from model: \(self.penShadowDeltaPixcelVal) (Index: \(self.roughnessIndex))")
            }
            
            if let cdModel = viewModel.cdThresholdModel {
                let predictedCD = cdModel.predict(x: self.roughnessIndex)
                self.cdDeltaThreshold = CGFloat(max(0.0, min(100.0, predictedCD)))
                print("Applied CD Threshold from model: \(self.cdDeltaThreshold) (Index: \(self.roughnessIndex))")
            }
        }
        
        if let transpModel = viewModel.transparencyModel {
            let predictedTransp = transpModel.predict(x: self.brightnessIndex)
            self.penShadowTransparencyVal = max(0.0, min(1.0, predictedTransp))
            print("Applied Transparency from model: \(self.penShadowTransparencyVal) (Index: \(self.brightnessIndex))")
        }
    }
    
    // MARK: - Log Functions
    
    private func saveHapticsLog() {
        NSSound(named: "Glass")?.play()
        
        let fileName = "haptics_log.csv"
        let sourceFile = URL(fileURLWithPath: #file)
        let projectDir = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        let fileURL = projectDir.appendingPathComponent(fileName)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateStr = formatter.string(from: Date())
        
        let img1Name = URL(fileURLWithPath: displayImgPath).lastPathComponent
        let img2Name = URL(fileURLWithPath: depthMapPath).lastPathComponent
        
        let csvLine = "\(dateStr),\(img1Name),\(img2Name),\(penShadowTransparencyVal),\(penShadowDeltaPixcelVal),\(cdDeltaThreshold),\(roughnessIndex),\(brightnessIndex)\n"
        
        do {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                let header = "Date,Image1,Image2,Transparency,DeltaPixel,CDThreshold,RoughnessIndex,BrightnessIndex\n"
                try header.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle.seekToEndOfFile()
            if let data = csvLine.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
            print("Log saved: \(csvLine)")
        } catch {
            print("Error saving CSV: \(error)")
        }
    }
    
    @MainActor
    private func savePaintedImage() {
        NSSound(named: "Glass")?.play()
        
        let sourceFile = URL(fileURLWithPath: #file)
        let projectDir = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        let paintedDir = projectDir.appendingPathComponent("painted")
        try? FileManager.default.createDirectory(at: paintedDir, withIntermediateDirectories: true, attributes: nil)
        
        let renderer = ImageRenderer(content: ZStack {
            if let bgImage1 = NSImage(contentsOf: URL(fileURLWithPath: displayImgPath)) {
                Image(nsImage: bgImage1).resizable().scaledToFill()
            }
            Canvas { context, size in
                for stroke in paintedPaths {
                    var path = Path()
                    if let first = stroke.points.first {
                        path.move(to: first)
                        for point in stroke.points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    context.stroke(path, with: .color(stroke.color), lineWidth: stroke.lineWidth)
                }
            }
        }
        .frame(width: screenWidth, height: screenHeight))
        
        if let nsImage = renderer.nsImage {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let dateStr = formatter.string(from: Date())
            let filename = "\(dateStr)_painted.png"
            let fileURL = paintedDir.appendingPathComponent(filename)
            
            if let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: fileURL)
                print("Painted image saved to: \(fileURL.path)")
            }
        }
    }
    
    // MARK: - Image Analysis
    
    private func calculateImageBrightnessStats(imagePath: String) {
        guard let platformImage = NSImage(contentsOf: URL(fileURLWithPath: imagePath)) else { return }
        guard let cgImage = platformImage.asCGImage else { return }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard let pixelData = cgImage.dataProvider?.data,
              let data = CFDataGetBytePtr(pixelData) else { return }
        
        let cx = Double(width) / 2.0
        let cy = Double(height) / 2.0
        let radius = (screenHeight * 0.4) / 2.0
        let radiusSq = radius * radius
        
        var yValues: [Double] = []
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        let minX = Int(max(0, cx - radius))
        let maxX = Int(min(Double(width), cx + radius))
        let minY = Int(max(0, cy - radius))
        let maxY = Int(min(Double(height), cy + radius))
        
        for x in minX..<maxX {
            for y in minY..<maxY {
                let dx = Double(x) - cx
                let dy = Double(y) - cy
                
                if dx*dx + dy*dy <= radiusSq {
                    let pixelInfo = (y * width + x) * bytesPerPixel
                    let r = Double(data[pixelInfo])
                    let g = Double(data[pixelInfo + 1])
                    let b = Double(data[pixelInfo + 2])
                    
                    let yVal = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    yValues.append(yVal)
                }
            }
        }
        
        guard !yValues.isEmpty else { return }
        
        let sum = yValues.reduce(0, +)
        let mean = sum / Double(yValues.count)
        
        let sortedY = yValues.sorted()
        let median: Double
        if sortedY.count % 2 == 1 {
            median = sortedY[sortedY.count / 2]
        } else {
            let mid1 = sortedY[sortedY.count / 2 - 1]
            let mid2 = sortedY[sortedY.count / 2]
            median = (mid1 + mid2) / 2.0
        }
        
        self.brightnessMean = mean
        self.brightnessMedian = median
        self.brightnessIndex = mean / 255.0
    }
    
    private func calculateCircleStdDev(map: [[Int]]) -> Double {
        let width = map.count
        guard width > 0 else { return 0.0 }
        let height = map[0].count
        guard height > 0 else { return 0.0 }
        
        let cx = Double(width) / 2.0
        let cy = Double(height) / 2.0
        let radius = (screenHeight * 0.4) / 2.0
        let radiusSq = radius * radius
        
        var pixelValues: [Double] = []
        
        let minX = Int(max(0, cx - radius))
        let maxX = Int(min(Double(width), cx + radius))
        let minY = Int(max(0, cy - radius))
        let maxY = Int(min(Double(height), cy + radius))
        
        for x in minX..<maxX {
            for y in minY..<maxY {
                let dx = Double(x) - cx
                let dy = Double(y) - cy
                
                if dx*dx + dy*dy <= radiusSq {
                    pixelValues.append(Double(map[x][y]))
                }
            }
        }
        
        guard !pixelValues.isEmpty else { return 0.0 }
        
        let mean = pixelValues.reduce(0, +) / Double(pixelValues.count)
        let sumSquaredDiffs = pixelValues.reduce(0) { $0 + pow($1 - mean, 2) }
        let variance = sumSquaredDiffs / Double(pixelValues.count)
        
        return sqrt(variance)
    }
    
    // MARK: - Pen Dynamics
    
    private func updatePenDynamics(newLocation: CGPoint?, tilt: NSPoint) {
        guard let newLocation = newLocation, !depthMapArray.isEmpty else { return }
        
        let smoothingFactor: CGFloat = 0.9
        let penThetaRaw: CGFloat = atan2(-tilt.y, tilt.x) + .pi/4.0
        let penAngleRaw: CGFloat = hypot(tilt.y, tilt.x)
        
        let prevLocation = self.previousPenLocation ?? newLocation
        let dx = newLocation.x - prevLocation.x
        let dy = newLocation.y - prevLocation.y
        
        var currentMoveAngle = self.penMovementAngleRaw
        if dx != 0 || dy != 0 {
            currentMoveAngle = atan2(dy, dx) + Double.pi/4.0 + Double.pi
        }
        
        self.penMovementAngleRaw = currentMoveAngle
        
        let newStabilizedPenTheta = stabilizedPenTheta * (1 - smoothingFactor) + penThetaRaw * smoothingFactor
        let newStabilizedPenAngle = stabilizedPenAngle * (1 - smoothingFactor) + penAngleRaw * smoothingFactor
        let penMovementAngle = self.stabilizedPenMovementAngle * (1 - smoothingFactor) + currentMoveAngle * smoothingFactor
        
        self.stabilizedPenTheta = newStabilizedPenTheta
        self.stabilizedPenAngle = newStabilizedPenAngle
        self.stabilizedPenMovementAngle = penMovementAngle
        
        let mapWidth = depthMapArray.count
        let mapHeight = depthMapArray.first?.count ?? 0
        let pX = Int(newLocation.x)
        let pY = Int(newLocation.y)
        
        var depthGradient: CGFloat = 0.0
        let moveDist = sqrt(dx*dx + dy*dy)
        
        if moveDist > 0.0 {
            let normX = dx / moveDist
            let normY = dy / moveDist
            
            let lookAheadDist: CGFloat = 3.0
            let targetX = Int(newLocation.x + normX * lookAheadDist)
            let targetY = Int(newLocation.y + normY * lookAheadDist)
            
            if pX >= 0 && pX < mapWidth && pY >= 0 && pY < mapHeight &&
                targetX >= 0 && targetX < mapWidth && targetY >= 0 && targetY < mapHeight {
                
                let currentDepth = CGFloat(depthMapArray[pX][pY])
                let nextDepth = CGFloat(depthMapArray[targetX][targetY])
                depthGradient = nextDepth - currentDepth
            }
        }
        
        if self.previousPenLocation == nil {
            self.currentShadowLocation = newLocation
            self.previousPenLocation = newLocation
            return
        }
        
        let now = Date()
        var cdRatio: CGFloat = 1.0
        
        if shadowState == .idle {
            if depthGradient > cdDeltaThreshold {
                shadowState = .resistance
                animationStartTime = now
            } else if depthGradient < -cdDeltaThreshold {
                shadowState = .accelerate
                animationStartTime = now
            }
        }
        
        switch shadowState {
        case .idle:
            currentShadowLocation = newLocation
            
        case .resistance:
            if let startTime = animationStartTime {
                let elapsed = now.timeIntervalSince(startTime)
                
                if elapsed < 0.3 {
                    cdRatio = -0.3
                    currentShadowLocation.x += dx * cdRatio
                    currentShadowLocation.y += dy * cdRatio
                    
                } else if elapsed < 0.4 {
                    let target = newLocation
                    let diffX = target.x - currentShadowLocation.x
                    let diffY = target.y - currentShadowLocation.y
                    let remainingTime = 0.4 - elapsed
                    let dt = 1.0 / 60.0
                    let stepRatio = CGFloat(dt / remainingTime)
                    
                    if stepRatio >= 1.0 {
                        currentShadowLocation = newLocation
                    } else {
                        currentShadowLocation.x += diffX * stepRatio
                        currentShadowLocation.y += diffY * stepRatio
                    }
                    
                } else {
                    shadowState = .idle
                    currentShadowLocation = newLocation
                }
            }
            
        case .accelerate:
            if let startTime = animationStartTime {
                let elapsed = now.timeIntervalSince(startTime)
                
                if elapsed < 0.3 {
                    cdRatio = 2.0
                    currentShadowLocation.x += dx * cdRatio
                    currentShadowLocation.y += dy * cdRatio
                    
                } else if elapsed < 0.4 {
                    let target = newLocation
                    let diffX = target.x - currentShadowLocation.x
                    let diffY = target.y - currentShadowLocation.y
                    let remainingTime = 0.4 - elapsed
                    let dt = 1.0 / 60.0
                    let stepRatio = CGFloat(dt / remainingTime)
                    
                    if stepRatio >= 1.0 {
                        currentShadowLocation = newLocation
                    } else {
                        currentShadowLocation.x += diffX * stepRatio
                        currentShadowLocation.y += diffY * stepRatio
                    }
                    
                } else {
                    shadowState = .idle
                    currentShadowLocation = newLocation
                }
            }
        }
        
        // ペイント描画処理
        if isPaintMode && penModel.pressure > 0 {
            let targetPoint: CGPoint
            switch paintSource {
            case .shadow:
                targetPoint = currentShadowLocation
            case .raw:
                targetPoint = newLocation
            }
            
            let tipPoint = CGPoint(
                x: targetPoint.x + pen_lib_posX,
                y: targetPoint.y + pen_lib_posY
            )
            
            if isDrawingStroke,
               let lastIdx = paintedPaths.indices.last,
               paintedPaths[lastIdx].color == paintColor {
                paintedPaths[lastIdx].points.append(tipPoint)
            } else {
                paintedPaths.append(PaintStroke(points: [tipPoint], color: paintColor, lineWidth: currentLineWidth))
                isDrawingStroke = true
            }
        }
        
        self.previousPenLocation = newLocation
    }
    
    // MARK: - Shadow Drawing
    
    private func drawShadows(context: inout GraphicsContext, canvasSize: CGSize, penLocation: CGPoint, tilt: NSPoint) {
        guard !depthMapArray.isEmpty, !penShadowShape.isEmpty else { return }
        
        let isCursorMode = (selectedCursorShape == .cursor)
        
        let penTheta: CGFloat
        let penAngle: CGFloat
        let penShadowLen: CGFloat
        let penXStep: CGFloat
        
        if isCursorMode {
            penTheta = CGFloat(Double.pi / 3) // Fixed angle 60 degrees
            penAngle = 0 // Treat as flat/upright for calculation purposes if needed, but we override effects
            penShadowLen = 100.0
            penXStep = 1.0 // Standard step
        } else {
            penTheta = self.stabilizedPenTheta
            penAngle = self.stabilizedPenAngle
            penXStep = max(1.0, (1-penAngle) * 2.0)
            penShadowLen = 200/penXStep
        }
        
        let cosTheta = cos(penTheta)
        let sinTheta = sin(penTheta)
        let baseXOffset = penLocation.x + pen_lib_posX
        let baseYOffset = penLocation.y + pen_lib_posY
        
        let basePosX = baseXOffset
        let basePosY = baseYOffset
        
        let penFadeOutPos: CGFloat = penShadowLen * 0.5
        
        let penShadowTransparency: Double = penShadowTransparencyVal
        
        let opacityBaseAngle = Double.pi/9.0
        
        let penShadowMoveScale: CGFloat  = penShadowDeltaPixcelVal * penShadowDeltaPixcelVal / 255.0
        let angleOpacity : Double
        
        if isCursorMode {
            angleOpacity = penShadowTransparency // Always visible
        } else {
            if Double(penAngle) < opacityBaseAngle && Double(penAngle) > opacityBaseAngle/2.0 {
                angleOpacity = penShadowTransparency * (2 * Double(penAngle) - opacityBaseAngle) / opacityBaseAngle
            } else if Double(penAngle) < opacityBaseAngle {
                angleOpacity = 0.0
            } else {
                angleOpacity = penShadowTransparency
            }
        }
        
        let mapWidth = depthMapArray.count
        let mapHeight = depthMapArray.first?.count ?? 0
        
        context.translateBy(x: penLocation.x + pen_lib_posX, y: penLocation.y + pen_lib_posY)
        context.rotate(by: Angle(radians: Double(penTheta)))
        
        var pathsByOpacity: [Path] = Array(repeating: Path(), count: 11)
        
        // Tilt-based shadow direction factor (only relevant if we want depth effect direction to change)
        // For cursor mode, if we want "no tilt influence", we should probably fix this too or keep it based on theta.
        // If theta is fixed 0, cos/sin are fixed.
        let shadowCosFactor = cos(-penTheta - Double.pi/7)
        let shadowSinFactor = sin(-penTheta - Double.pi/7)
        
        for x in stride(from: 0, to: penShadowLen, by: penShadowCellSize) {
            let x_int = Int(x)
            var currentOpacityX = penShadowTransparency
            
            if !isCursorMode {
                if x >= penFadeOutPos {
                    currentOpacityX = Double((x - penShadowLen) * CGFloat(penShadowTransparency) / (penFadeOutPos - penShadowLen))
                }
            }
            
            // For cursor mode, we might need a safer index check if shape is different length?
            // shape loading handles its own length, but let's be safe.
            let shapeIndex = Int(CGFloat(x_int) * penXStep)
            guard shapeIndex < penShadowShape.count else { continue }
            let penWidthAtX = penShadowShape[shapeIndex]
            
            let penFadeOutPosY = 0.6 * CGFloat(penWidthAtX/2)
            
            for y in stride(from: -penWidthAtX / 2, to: penWidthAtX / 2, by: penShadowCellSize) {
                var currentOpacityY = penShadowTransparency
                
                let localX = x
                let localY = y
                
                let rotX = localX * cosTheta - localY * sinTheta
                let rotY = localX * sinTheta + localY * cosTheta
                let screenX = baseXOffset + rotX
                let screenY = baseYOffset + rotY
                
                let checkX = Int(screenX + offsetX)
                let checkY = Int(screenY + offsetY)
                let baseCheckX = Int(basePosX + offsetX)
                let baseCheckY = Int(basePosY + offsetY)
                
                if checkX >= 0 && checkX < mapWidth && checkY >= 0 && checkY < mapHeight &&
                    baseCheckX >= 0 && baseCheckX < mapWidth && baseCheckY >= 0 && baseCheckY < mapHeight {
                    
                    if !isCursorMode {
                        if abs(y) >= penFadeOutPosY {
                            currentOpacityY = Double((abs(y) - penWidthAtX/2) * CGFloat(penShadowTransparency) / (penFadeOutPosY - (penWidthAtX/2)))
                        }
                    }
                    
                    let bufferOpacity: Double = min(currentOpacityX, currentOpacityY)
                    let currentOpacity: Double = min(bufferOpacity, angleOpacity)
                    
                    if currentOpacity < 0.01 { continue }
                    
                    let depthDiff = CGFloat(depthMapArray[checkX][checkY] - depthMapArray[baseCheckX][baseCheckY])
                    
                    let shadowX = x + penShadowMoveScale * depthDiff * shadowCosFactor
                    let shadowY = y + penShadowMoveScale * depthDiff * shadowSinFactor
                    
                    let opacityIndex = min(10, max(0, Int(currentOpacity * 10)))
                    pathsByOpacity[opacityIndex].addRect(CGRect(x: shadowX, y: shadowY, width: penShadowCellSize, height: penShadowCellSize))
                }
            }
        }
        
        for i in 1...10 {
            if !pathsByOpacity[i].isEmpty {
                let opacity = Double(i) / 10.0
                context.fill(pathsByOpacity[i], with: .color(.black.opacity(opacity)))
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadPenShapeFromCSV(filename: String) -> [CGFloat] {
        guard let filepath = Bundle.main.path(forResource: filename, ofType: "csv") else {
            let length = 400
            var shape: [CGFloat] = []
            for i in 0..<length {
                let width = max(0, CGFloat(30 - Double(i) * 0.1))
                shape.append(width)
            }
            return shape
        }
        do {
            let contents = try String(contentsOf: URL(fileURLWithPath: filepath), encoding: .utf8)
            let rows = contents.components(separatedBy: .newlines)
            return rows.dropFirst().compactMap { row in
                let columns = row.components(separatedBy: ",")
                if columns.count > 1, let value = Float(columns[1]) {
                    return CGFloat(value)
                }
                return nil
            }
        } catch {
            return []
        }
    }
    
    private func processDepthMap(imagePath: String) -> [[Int]]? {
        guard let platformImage = NSImage(contentsOf: URL(fileURLWithPath: imagePath)) else { return nil }
        guard let cgImage = platformImage.asCGImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard let pixelData = cgImage.dataProvider?.data,
              let data = CFDataGetBytePtr(pixelData) else { return nil }
        
        var minAvg = 255
        var maxAvg = 0
        var rawAverages = [Int]()
        rawAverages.reserveCapacity(width * height)
        
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelInfo = (y * width + x) * bytesPerPixel
                let r = Int(data[pixelInfo])
                let g = Int(data[pixelInfo + 1])
                let b = Int(data[pixelInfo + 2])
                let avg = (r + g + b) / 3
                rawAverages.append(avg)
                minAvg = min(minAvg, avg)
                maxAvg = max(maxAvg, avg)
            }
        }
        
        var mapArray = Array(repeating: Array(repeating: 0, count: height), count: width)
        let range = Float(maxAvg - minAvg)
        guard range > 0 else { return mapArray }
        
        for y in 0..<height {
            for x in 0..<width {
                let avg = rawAverages[y * width + x]
                if x < mapArray.count && y < mapArray[0].count {
                    mapArray[x][y] = Int(Float(avg - minAvg) / range * 255.0)
                }
            }
        }
        return mapArray
    }
}
