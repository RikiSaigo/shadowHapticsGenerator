import SwiftUI
import AppKit
import Combine

// MARK: - Image Generator ViewModel

/// 画像生成とAPI通信を管理するViewModel
@MainActor
class ImageGeneratorViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var prompt: String = ""
    @Published var image1: NSImage? = nil
    @Published var image2: NSImage? = nil
    @Published var isLoading: Bool = false
    @Published var statusMessage: String? = nil
    @Published var errorMessage: String? = nil
    
    @Published var isGeneratingOrResult: Bool = false
    @Published var isProcessComplete: Bool = false
    
    // MARK: - Saved Paths
    var savedImage1Path: URL?
    var savedDepthMapPath: URL?
    
    // MARK: - Regression Models
    var deltaPixelModel: PolynomialRegressionModel?
    var cdThresholdModel: PolynomialRegressionModel?
    var transparencyModel: PolynomialRegressionModel?
    
    // MARK: - Public Methods
    
    /// 状態をリセット
    func reset() {
        self.prompt = ""
        self.image1 = nil
        self.image2 = nil
        self.statusMessage = nil
        self.errorMessage = nil
        self.isGeneratingOrResult = false
        self.isProcessComplete = false
        self.savedImage1Path = nil
        self.savedDepthMapPath = nil
        self.isLoading = false
    }
    
    /// 生成状態を開始
    func startGenerationState() {
        self.isGeneratingOrResult = true
        self.isLoading = true
    }
    
    /// 画像生成プロセスを実行
    func generateProcess() async {
        guard !prompt.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        isProcessComplete = false
        statusMessage = "Generating Display Image..."
        
        if deltaPixelModel == nil || cdThresholdModel == nil || transparencyModel == nil {
            await buildRegressionModels()
        }
        
        // 画像1 生成時間計測
        let startTime1 = Date()
        
        guard let img1Raw = await generateFirstImage() else {
            statusMessage = "画像1の生成に失敗しました"
            isLoading = false
            return
        }
        
        let duration1 = Date().timeIntervalSince(startTime1)
        
        let targetSize = NSSize(width: screenWidth, height: screenHeight)
        guard let resizedImg1 = img1Raw.resized(to: targetSize) else {
            statusMessage = "生成画像のリサイズに失敗しました"
            isLoading = false
            return
        }
        self.image1 = resizedImg1
        
        await generateDepthAndFinalize(sourceImage: resizedImg1, img1Duration: duration1)
    }
    
    /// アップロードされた画像を処理
    func processUploadedImage(image: NSImage) {
        self.isGeneratingOrResult = true
        self.isLoading = true
        self.statusMessage = "Processing uploaded image..."
        self.errorMessage = nil
        self.isProcessComplete = false
        
        let targetSize = NSSize(width: screenWidth, height: screenHeight)
        guard let croppedImg1 = image.resizedAspectFill(to: targetSize) else {
            self.errorMessage = "画像のトリミングリサイズに失敗しました"
            self.isLoading = false
            return
        }
        self.image1 = croppedImg1
        
        Task {
            if deltaPixelModel == nil || cdThresholdModel == nil || transparencyModel == nil {
                await buildRegressionModels()
            }
            await generateDepthAndFinalize(sourceImage: croppedImg1, img1Duration: 0.0)
        }
    }
    
    // MARK: - Private Methods
    
    /// CSVから回帰モデルを構築
    private func buildRegressionModels() async {
        print("Building regression models from CSV...")
        let fileName = "haptics_log.csv"
        let sourceFile = URL(fileURLWithPath: #file)
        let projectDir = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        let fileURL = projectDir.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            print("CSV file not found or unreadable at: \(fileURL.path)")
            return
        }

        var roughnessData: [Double] = []
        var brightnessData: [Double] = []
        var deltaPixelData: [Double] = []
        var cdThresholdData: [Double] = []
        var transparencyData: [Double] = []

        let lines = content.components(separatedBy: .newlines)
        for line in lines.dropFirst() {
            let parts = line.components(separatedBy: ",")
            if parts.count >= 8,
               let transp = Double(parts[3]),
               let deltaP = Double(parts[4]),
               let cdTh = Double(parts[5]),
               let rough = Double(parts[6]),
               let bright = Double(parts[7]) {
                
                transparencyData.append(transp)
                deltaPixelData.append(deltaP)
                cdThresholdData.append(cdTh)
                roughnessData.append(rough)
                brightnessData.append(bright)
            }
        }

        if roughnessData.count >= 3 {
            self.deltaPixelModel = PolynomialRegressionModel.fit(xValues: roughnessData, yValues: deltaPixelData)
            self.cdThresholdModel = PolynomialRegressionModel.fit(xValues: roughnessData, yValues: cdThresholdData)
        }
        if brightnessData.count >= 3 {
            self.transparencyModel = PolynomialRegressionModel.fit(xValues: brightnessData, yValues: transparencyData)
        }
    }
    
    /// Depth Mapを生成して最終処理
    private func generateDepthAndFinalize(sourceImage: NSImage, img1Duration: Double) async {
        statusMessage = "Generating Height Map Image..."
        
        let startTime2 = Date()
        
        guard let img2Raw = await generateDepthMap(sourceImage: sourceImage) else {
            statusMessage = "Height Mapの生成に失敗しました"
            isLoading = false
            return
        }
        
        let duration2 = Date().timeIntervalSince(startTime2)
        
        let targetSize = NSSize(width: screenWidth, height: screenHeight)
        guard let resizedImg2 = img2Raw.resized(to: targetSize) else {
            statusMessage = "Height Mapのリサイズに失敗しました"
            isLoading = false
            return
        }
        self.image2 = resizedImg2
        
        statusMessage = "画像を保存中..."
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename1 = "\(timestamp)_rgb.png"
        let filename2 = "\(timestamp)_depth.png"
        
        let savedPath1 = saveImageToTextureAlbum(image: sourceImage, fileName: filename1)
        let savedPath2 = saveImageToTextureAlbum(image: resizedImg2, fileName: filename2)
        
        if savedPath1 != nil && savedPath2 != nil {
            statusMessage = "Processing Height Map..."
            self.savedImage1Path = savedPath1
            self.savedDepthMapPath = savedPath2
            
            saveGenerationLog(
                prompt: self.prompt,
                img1Name: filename1,
                img2Name: filename2,
                time1: img1Duration,
                time2: duration2
            )
            
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.isProcessComplete = true
            
        } else {
            statusMessage = "保存に失敗しました。Sandbox設定を確認してください。"
        }
        isLoading = false
    }
    
    /// 生成ログをCSVに保存
    private func saveGenerationLog(prompt: String, img1Name: String, img2Name: String, time1: Double, time2: Double) {
        let fileName = "generation_log.csv"
        let sourceFile = URL(fileURLWithPath: #file)
        let projectDir = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        let fileURL = projectDir.appendingPathComponent(fileName)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateStr = formatter.string(from: Date())
        
        let sanitizedPrompt = prompt.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "\n", with: " ")
        let totalTime = time1 + time2
        
        let csvLine = "\(dateStr),\(sanitizedPrompt),\(img1Name),\(img2Name),\(String(format: "%.3f", time1)),\(String(format: "%.3f", time2)),\(String(format: "%.3f", totalTime))\n"
        
        do {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                let header = "Date,Prompt,Image1_Name,Image2_Name,Time1_Sec,Time2_Sec,TotalTime_Sec\n"
                try header.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle.seekToEndOfFile()
            if let data = csvLine.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
            print("Generation log saved: \(csvLine)")
        } catch {
            print("Error saving generation log: \(error)")
        }
    }
    
    /// 画像をhistoryフォルダに保存
    private func saveImageToTextureAlbum(image: NSImage, fileName: String, sourceFilePath: String = #file) -> URL? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        
        let sourceFileURL = URL(fileURLWithPath: sourceFilePath)
        let projectDir = sourceFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let projectHistoryDir = projectDir.appendingPathComponent("history")
        
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("TextureAlbumHistory")
        
        do {
            try FileManager.default.createDirectory(at: projectHistoryDir, withIntermediateDirectories: true, attributes: nil)
            let fileURL = projectHistoryDir.appendingPathComponent(fileName)
            try pngData.write(to: fileURL)
            return fileURL
        } catch {
            print("プロジェクトフォルダへの保存失敗: \(error). ドキュメントフォルダを試みます。")
            
            guard let fallbackDir = docDir else {
                DispatchQueue.main.async {
                    self.errorMessage = "保存失敗: 保存先が見つかりません"
                }
                return nil
            }
            
            do {
                try FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true, attributes: nil)
                let fileURL = fallbackDir.appendingPathComponent(fileName)
                try pngData.write(to: fileURL)
                return fileURL
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "保存失敗: \(error.localizedDescription)"
                }
                return nil
            }
        }
    }
    
    /// 表示用画像を生成
    private func generateFirstImage() async -> NSImage? {
        guard let url = AppConfig.geminiRequestUrl else { return nil }
        let enhancedPrompt = PromptConfig.displayImagePrompt(for: prompt)
        
        let body: [String: Any] = [
            "contents": [["parts": [["text": enhancedPrompt]]]],
            "generationConfig": ["responseModalities": ["IMAGE"], "temperature": 0.9]
        ]
        return await sendRequest(url: url, body: body)
    }
    
    /// Depth Map画像を生成
    private func generateDepthMap(sourceImage: NSImage) async -> NSImage? {
        guard let url = AppConfig.geminiRequestUrl else { return nil }
        guard let tiffData = sourceImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        let base64Image = jpegData.base64EncodedString()
        
        let body: [String: Any] = [
            "contents": [[ "parts": [
                ["text": PromptConfig.depthMapPrompt],
                ["inlineData": ["mimeType": "image/jpeg", "data": base64Image]]
            ]]],
            "generationConfig": ["responseModalities": ["IMAGE"], "temperature": 0.9]
        ]
        return await sendRequest(url: url, body: body)
    }
    
    /// Gemini APIにリクエストを送信
    private func sendRequest(url: URL, body: [String: Any]) async -> NSImage? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                var errorDetails = "HTTP Status: \(httpResponse.statusCode)"
                if let errorJson = try? JSONDecoder().decode(GeminiResponse.self, from: data),
                   let msg = errorJson.error?.message {
                    errorDetails += "\nMessage: \(msg)"
                }
                print(errorDetails)
                DispatchQueue.main.async { self.errorMessage = errorDetails }
                return nil
            }
            
            let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
            if let parts = decoded.candidates?.first?.content?.parts {
                if let imagePart = parts.first(where: { $0.inlineData != nil }),
                   let b64 = imagePart.inlineData?.data,
                   let data = Data(base64Encoded: b64) {
                    return NSImage(data: data)
                }
            }
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
        }
        return nil
    }
}
