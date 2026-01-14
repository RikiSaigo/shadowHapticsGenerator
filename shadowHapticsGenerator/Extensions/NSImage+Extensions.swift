import AppKit

// MARK: - NSImage Extensions

extension NSImage {
    /// NSImageをCGImageに変換
    var asCGImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: self.size)
        return self.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
    
    /// 指定サイズにリサイズ（アスペクト比を無視）
    func resized(to newSize: NSSize) -> NSImage? {
        if let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(newSize.width), pixelsHigh: Int(newSize.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) {
            bitmapRep.size = newSize
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
            self.draw(in: NSRect(x: 0, y: 0, width: newSize.width, height: newSize.height),
                      from: .zero, operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            let resizedImage = NSImage(size: newSize)
            resizedImage.addRepresentation(bitmapRep)
            return resizedImage
        }
        return nil
    }
    
    /// アスペクトフィル（画像中央からクロップしてリサイズ）
    func resizedAspectFill(to targetSize: NSSize) -> NSImage? {
        let sourceSize = self.size
        guard sourceSize.width > 0 && sourceSize.height > 0 else { return nil }
        
        let widthRatio = targetSize.width / sourceSize.width
        let heightRatio = targetSize.height / sourceSize.height
        let scale = max(widthRatio, heightRatio)
        
        let cropWidth = targetSize.width / scale
        let cropHeight = targetSize.height / scale
        
        let xOffset = (sourceSize.width - cropWidth) / 2.0
        let yOffset = (sourceSize.height - cropHeight) / 2.0
        
        let sourceRect = NSRect(x: xOffset, y: yOffset, width: cropWidth, height: cropHeight)
        let destRect = NSRect(origin: .zero, size: targetSize)
        
        if let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(targetSize.width), pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) {
            bitmapRep.size = targetSize
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
            NSGraphicsContext.current?.imageInterpolation = .high
            self.draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            let newImage = NSImage(size: targetSize)
            newImage.addRepresentation(bitmapRep)
            return newImage
        }
        return nil
    }
}
