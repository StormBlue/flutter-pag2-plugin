import Foundation
import Flutter
import CoreVideo
import UIKit
import libpag

typealias FrameUpdateCallback = () -> Void
typealias PAGEventCallback = (String) -> Void

/// Pag纹理渲染类
class TGFlutterPagRender: NSObject, FlutterTexture {
    static let eventStart = "onAnimationStart"
    static let eventEnd = "onAnimationEnd"
    static let eventCancel = "onAnimationCancel"
    static let eventRepeat = "onAnimationRepeat"

    /// 当前pag的size
    private(set) var size: CGSize = .zero

    var textureId: Int64 = -1

    private var surface: PAGSurface?
    private var player: PAGPlayer?
    private var pagFile: PAGFile?
    private var initProgress: Double = 0
    private var endEvent: Bool = false

    private var frameUpdateCallback: FrameUpdateCallback?
    private var eventCallback: PAGEventCallback?
    private var displayLink: CADisplayLink?
    private var repeatCount: Int = 0
    private var startTime: Int64 = 0
    private var currRepeatCount: Int64 = 0

    // 高精度计时器 - 替代 C++ std::chrono
    private static let processStartTime = CACurrentMediaTime()
    private static func getCurrentTimeUS() -> Int64 {
        return Int64((CACurrentMediaTime() - processStartTime) * 1_000_000)
    }

    // MARK: - FlutterTexture

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let player = player else { return nil }

        var duration = player.duration()
        if duration <= 0 {
            duration = 1
        }

        let timestamp = TGFlutterPagRender.getCurrentTimeUS()
        if startTime <= 0 {
            startTime = timestamp
        }

        let count = (timestamp - startTime) / duration
        var value: Double = 0

        if repeatCount >= 0 && count >= Int64(repeatCount) {
            value = 1
            if !endEvent {
                endEvent = true
                eventCallback?(TGFlutterPagRender.eventEnd)
            }
        } else {
            endEvent = false
            let playTime = (timestamp - startTime) % duration
            value = Double(playTime) / Double(duration)
            if currRepeatCount < count {
                currRepeatCount = count
                eventCallback?(TGFlutterPagRender.eventRepeat)
            }
        }

        player.setProgress(value)
        player.flush()

        guard let surface = surface, let pixelBuffer = surface.getCVPixelBuffer() else {
            return nil
        }
        return pixelBuffer.retain()
    }

    // MARK: - Setup

    func setUp(pagData: Data, progress: Double,
               frameUpdateCallback: @escaping FrameUpdateCallback,
               eventCallback: @escaping PAGEventCallback) {
        self.frameUpdateCallback = frameUpdateCallback
        self.eventCallback = eventCallback
        self.initProgress = progress

        if TGFlutterWorkerExecutor.sharedInstance.enableMultiThread {
            // 防止setup和release、dealloc并行争抢
            objc_sync_enter(self)
            setUpPlayer(pagData: pagData)
            objc_sync_exit(self)
        } else {
            setUpPlayer(pagData: pagData)
        }
    }

    private func setUpPlayer(pagData: Data) {
        let nsData = pagData as NSData
        pagFile = PAGFile.load(nsData.bytes, size: nsData.length)

        if player == nil {
            player = PAGPlayer()
        }

        guard let pagFile = pagFile else { return }
        player?.setComposition(pagFile)
        surface = PAGSurface.makeOffscreen(CGSize(width: CGFloat(pagFile.width()), height: CGFloat(pagFile.height())))
        player?.setSurface(surface)
        player?.setProgress(initProgress)
        player?.flush()
        size = CGSize(width: CGFloat(pagFile.width()), height: CGFloat(pagFile.height()))
        frameUpdateCallback?()
    }

    // MARK: - Render Control

    func startRender() {
        if displayLink == nil {
            displayLink = CADisplayLink(target: self, selector: #selector(update))
            displayLink?.add(to: .main, forMode: .common)
        }
        if startTime <= 0 {
            startTime = TGFlutterPagRender.getCurrentTimeUS()
        }
        eventCallback?(TGFlutterPagRender.eventStart)
    }

    func stopRender() {
        displayLink?.invalidate()
        displayLink = nil
        player?.setProgress(initProgress)
        player?.flush()
        frameUpdateCallback?()
        if !endEvent {
            endEvent = true
            eventCallback?(TGFlutterPagRender.eventEnd)
        }
        eventCallback?(TGFlutterPagRender.eventCancel)
    }

    func pauseRender() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func setRepeatCount(_ count: Int) {
        repeatCount = count
    }

    func setVideoEnabled(_ enabled: Bool) {
        player?.setVideoEnabled(enabled)
    }

    func setUseDiskCache(_ enabled: Bool) {
        player?.setUseDiskCache(enabled)
    }

    func setCacheScale(_ scale: Float) {
        player?.setCacheScale(scale)
    }

    func setMaxFrameRate(_ rate: Float) {
        player?.setMaxFrameRate(rate)
    }

    func setProgress(_ progress: Double) {
        player?.setProgress(progress)
        player?.flush()
        frameUpdateCallback?()
    }

    func getLayersUnderPoint(_ point: CGPoint) -> [String] {
        guard let layers = player?.getLayersUnderPoint(point) as? [PAGLayer] else { return [] }
        return layers.compactMap { $0.layerName() }
    }

    @objc private func update() {
        frameUpdateCallback?()
    }

    // MARK: - Cleanup

    func invalidateDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func clearSurface() {
        guard let surface = surface else { return }
        if TGFlutterWorkerExecutor.sharedInstance.enableMultiThread {
            objc_sync_enter(self)
            surface.freeCache()
            surface.clearAll()
            objc_sync_exit(self)
        } else {
            surface.freeCache()
            surface.clearAll()
        }
    }

    /// 清除Pagrender时序
    func clearPagState() {
        if TGFlutterWorkerExecutor.sharedInstance.enableMultiThread {
            objc_sync_enter(self)
            startTime = -1
            endEvent = false
            objc_sync_exit(self)
        } else {
            startTime = -1
            endEvent = false
        }
    }

    deinit {
        frameUpdateCallback = nil
        eventCallback = nil
        surface = nil
        pagFile = nil
        player = nil
    }
}
