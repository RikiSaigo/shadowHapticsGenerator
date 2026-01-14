import SwiftUI
import AppKit

// MARK: - Pen Input View (AppKit連携)

/// AppKitのペン入力イベントをSwiftUIに橋渡しするNSViewRepresentable
struct PenInputView: NSViewRepresentable {
    @ObservedObject var model: PenInputModel
    var shouldHideSystemCursor: Bool
    
    func makeNSView(context: Context) -> PenEventHandlingView {
        let view = PenEventHandlingView()
        view.model = model
        view.shouldHideSystemCursor = shouldHideSystemCursor
        return view
    }
    
    func updateNSView(_ nsView: PenEventHandlingView, context: Context) {
        nsView.shouldHideSystemCursor = shouldHideSystemCursor
    }
}

// MARK: - Pen Event Handling View (NSView)

/// ペン入力イベントを処理するNSViewサブクラス
class PenEventHandlingView: NSView {
    weak var model: PenInputModel?
    private var monitor: Any?
    
    var shouldHideSystemCursor: Bool = false {
        didSet {
            if shouldHideSystemCursor {
                NSCursor.hide()
            } else {
                NSCursor.unhide()
            }
        }
    }
    
    // 重要: これをtrueにすることで、左上原点の座標系（SwiftUIと同じ）で扱えるようにする
    override var isFlipped: Bool {
        return true
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if self.window != nil && shouldHideSystemCursor {
            NSCursor.hide()
        }
        
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .tabletPoint]) { [weak self] event in
                self?.handleGlobalEvent(event)
                return event
            }
        }
    }
    
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            NSCursor.unhide()
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
    
    /// グローバルイベントハンドラ
    private func handleGlobalEvent(_ event: NSEvent) {
        let pressure = CGFloat(event.pressure)
        let tilt = event.tilt
        let locationInWindow = event.locationInWindow
        
        // window座標(左下原点)から、このViewのローカル座標(左上原点)に変換する
        let convertedLocation = self.convert(locationInWindow, from: nil)
        
        DispatchQueue.main.async {
            self.model?.location = convertedLocation
            self.model?.pressure = pressure
            self.model?.tilt = tilt
        }
    }
}
