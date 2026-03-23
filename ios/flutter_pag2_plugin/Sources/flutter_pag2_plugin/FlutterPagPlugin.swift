import Flutter
import UIKit

// MARK: - Constants

private enum Method {
    static let getPlatformVersion = "getPlatformVersion"
    static let initPag = "initPag"
    static let release = "release"
    static let start = "start"
    static let stop = "stop"
    static let pause = "pause"
    static let setProgress = "setProgress"
    static let getLayersUnderPoint = "getLayersUnderPoint"
    static let enableCache = "enableCache"
    static let setCacheSize = "setCacheSize"
    static let enableMultiThread = "enableMultiThread"
    static let enableReuse = "enableReuse"
    static let setVideoEnabled = "setVideoEnabled"
    static let setUseDiskCache = "setUseDiskCache"
    static let setCacheScale = "setCacheScale"
    static let setMaxFrameRate = "setMaxFrameRate"
}

private enum Arg {
    static let textureId = "textureId"
    static let assetName = "assetName"
    static let package = "package"
    static let url = "url"
    static let bytesData = "bytesData"
    static let repeatCount = "repeatCount"
    static let initProgress = "initProgress"
    static let autoPlay = "autoPlay"
    static let width = "width"
    static let height = "height"
    static let pointX = "x"
    static let pointY = "y"
    static let progress = "progress"
    static let pagEvent = "PAGEvent"
    static let cacheEnabled = "cacheEnabled"
    static let cacheSize = "cacheSize"
    static let multiThreadEnabled = "multiThreadEnabled"
    static let reuse = "reuse"
    static let reuseKey = "reuseKey"
    static let viewId = "viewId"
    static let reuseEnabled = "reuseEnabled"
    static let frameAvailable = "frameAvailable"
    static let videoEnabled = "videoEnabled"
    static let useDiskCache = "useDiskCache"
    static let cacheScale = "cacheScale"
    static let maxFrameRate = "maxFrameRate"
}

private enum Callback {
    static let playCallback = "PAGCallback"
    static let eventStart = "onAnimationStart"
    static let eventEnd = "onAnimationEnd"
    static let eventCancel = "onAnimationCancel"
    static let eventRepeat = "onAnimationRepeat"
    static let eventUpdate = "onAnimationUpdate"
}

// MARK: - FlutterPagPlugin

@objc(FlutterPagPlugin)
public class FlutterPagPlugin: NSObject, FlutterPlugin {

    /// flutter引擎注册的textures对象
    private weak var textures: FlutterTextureRegistry?
    /// flutter引擎注册的registrar对象
    private weak var registrar: FlutterPluginRegistrar?
    /// 保存textureId跟render对象的对应关系
    private var renderMap: [Int64: TGFlutterPagRender] = [:]
    /// pag对象的缓存
    private lazy var cache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.totalCostLimit = 64 * 1024 * 1024 // 缓存64m
        c.countLimit = 32
        return c
    }()
    /// 用于通信的channel
    private var channel: FlutterMethodChannel!
    /// 缓存TGFlutterPagRender textureId，renderMap持有相应TGFlutterPagRender(release完成的)
    private var freeEntryPool: [Int64] = []
    /// 缓存TGFlutterPagRender textureId，release中的。处理release异步并行超出maxFreePoolSize
    private var preFreeEntryPool: [Int64] = []
    /// 开启TGFlutterPagRender 缓存
    private var enableRenderCache: Bool = true
    /// TGFlutterPagRender 缓存大小
    private var maxFreePoolSize: Int = 10
    /// 开启TGFlutterPagRender 复用
    private var isReuseEnabled: Bool = false
    /// 保存reuseKey和对应复用信息对象
    private var reuseMap: [String: ReuseItem] = [:]

    // MARK: - FlutterPlugin Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_pag2_plugin",
                                           binaryMessenger: registrar.messenger())
        let instance = FlutterPagPlugin()
        instance.textures = registrar.textures()
        instance.registrar = registrar
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: - Method Dispatch

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments
        switch call.method {
        case Method.getPlatformVersion:
            result("iOS " + UIDevice.current.systemVersion)
        case Method.initPag:
            handleInitPag(arguments, result: result)
        case Method.start:
            handleStart(arguments, result: result)
        case Method.stop:
            handleStop(arguments, result: result)
        case Method.pause:
            handlePause(arguments, result: result)
        case Method.setProgress:
            handleSetProgress(arguments, result: result)
        case Method.release:
            handleRelease(arguments, result: result)
        case Method.getLayersUnderPoint:
            handleGetLayersUnderPoint(arguments, result: result)
        case Method.enableCache:
            handleEnableCache(arguments, result: result)
        case Method.setCacheSize:
            handleSetCacheSize(arguments, result: result)
        case Method.enableMultiThread:
            handleEnableMultiThread(arguments, result: result)
        case Method.enableReuse:
            handleEnableReuse(arguments, result: result)
        case Method.setVideoEnabled:
            handleSetVideoEnabled(arguments, result: result)
        case Method.setUseDiskCache:
            handleSetUseDiskCache(arguments, result: result)
        case Method.setCacheScale:
            handleSetCacheScale(arguments, result: result)
        case Method.setMaxFrameRate:
            handleSetMaxFrameRate(arguments, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Texture ID Validation

    private func validTextureId(from arguments: Any?) -> Int64? {
        guard let args = arguments as? [String: Any],
              let textureIdNum = args[Arg.textureId] as? NSNumber else {
            return nil
        }
        let textureId = textureIdNum.int64Value
        guard textureId >= 0 else { return nil }
        return textureId
    }

    // MARK: - getLayersUnderPoint

    private func handleGetLayersUnderPoint(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let textureId = validTextureId(from: arguments),
              let args = arguments as? [String: Any] else {
            result(NSNumber(value: -1))
            return
        }
        let x = (args[Arg.pointX] as? NSNumber)?.doubleValue ?? 0
        let y = (args[Arg.pointY] as? NSNumber)?.doubleValue ?? 0
        let render = renderMap[textureId]
        let names = render?.getLayersUnderPoint(CGPoint(x: x, y: y)) ?? []
        result(names)
    }

    // MARK: - release

    private func handleRelease(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let textureId = validTextureId(from: arguments),
              let args = arguments as? [String: Any] else {
            result(NSNumber(value: -1))
            return
        }

        let reuse = (args[Arg.reuse] as? NSNumber)?.boolValue ?? false
        let reuseKey = args[Arg.reuseKey] as? String
        let viewId = (args[Arg.viewId] as? NSNumber)?.intValue ?? -1

        if isReuseEnabled && reuse, let reuseKey = reuseKey, !reuseKey.isEmpty {
            if let reuseItem = reuseMap[reuseKey], reuseItem.getTextureId() == textureId {
                reuseItem.usingViewSet.remove(NSNumber(value: viewId))
                if reuseItem.usingViewSet.count <= 0 {
                    // 复用列表为空 清除复用
                    reuseMap.removeValue(forKey: reuseKey)
                } else {
                    result("")
                    return
                }
            }
        }

        guard let render = renderMap[textureId] else {
            let flutterError = FlutterError(code: "-1102", message: "render异常", details: nil)
            result(flutterError)
            onInitPagError(reuse: reuse, reuseKey: reuseKey, flutterError: flutterError)
            return
        }

        // 标记surface是否正常渲染过，不正常则不走缓存（与Android端对等）
        let frameAvailable = (args[Arg.frameAvailable] as? NSNumber)?.boolValue ?? true

        // 防止并行加入freeEntryPool超过maxFreePoolSize，且仅缓存已正常渲染的render
        let shouldAddToFreePool = enableRenderCache && preFreeEntryPool.count < maxFreePoolSize && frameAvailable
        render.invalidateDisplayLink()

        if shouldAddToFreePool {
            preFreeEntryPool.append(textureId)
            // 异步并行release异常时序处理
            weak var weakSelf = self
            TGFlutterWorkerExecutor.sharedInstance.post {
                render.clearSurface()
                render.clearPagState()
                DispatchQueue.main.async {
                    weakSelf?.freeEntryPool.append(textureId)
                    result("")
                }
            }
        } else {
            textures?.unregisterTexture(textureId)
            render.textureId = -1
            renderMap.removeValue(forKey: textureId)
            result("")
        }
    }

    // MARK: - setProgress

    private func handleSetProgress(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let textureId = validTextureId(from: arguments),
              let args = arguments as? [String: Any] else {
            result(NSNumber(value: -1))
            return
        }
        let progress = (args[Arg.progress] as? NSNumber)?.doubleValue ?? 0.0
        let render = renderMap[textureId]
        render?.setProgress(progress)
        result("")
    }

    // MARK: - setVideoEnabled

    private func handleSetVideoEnabled(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let textureId = validTextureId(from: arguments),
              let args = arguments as? [String: Any] else {
            result(NSNumber(value: -1))
            return
        }
        let videoEnabled = (args[Arg.videoEnabled] as? NSNumber)?.boolValue ?? true
        let render = renderMap[textureId]
        render?.setVideoEnabled(videoEnabled)
        result("")
    }

    // MARK: - setUseDiskCache

    private func handleSetUseDiskCache(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let textureId = validTextureId(from: arguments),
              let args = arguments as? [String: Any] else {
            result(NSNumber(value: -1))
            return
        }
        let useDiskCache = (args[Arg.useDiskCache] as? NSNumber)?.boolValue ?? false
        let render = renderMap[textureId]
        render?.setUseDiskCache(useDiskCache)
        result("")
    }

    // MARK: - setCacheScale

    private func handleSetCacheScale(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let textureId = validTextureId(from: arguments),
              let args = arguments as? [String: Any] else {
            result(NSNumber(value: -1))
            return
        }
        let cacheScale = (args[Arg.cacheScale] as? NSNumber)?.floatValue ?? 1.0
        let render = renderMap[textureId]
        render?.setCacheScale(cacheScale)
        result("")
    }

    // MARK: - setMaxFrameRate

    private func handleSetMaxFrameRate(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let textureId = validTextureId(from: arguments),
              let args = arguments as? [String: Any] else {
            result(NSNumber(value: -1))
            return
        }
        let maxFrameRate = (args[Arg.maxFrameRate] as? NSNumber)?.floatValue ?? 60.0
        let render = renderMap[textureId]
        render?.setMaxFrameRate(maxFrameRate)
        result("")
    }

    // MARK: - pause

    private func handlePause(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let textureId = validTextureId(from: arguments) else {
            result(NSNumber(value: -1))
            return
        }
        let render = renderMap[textureId]
        render?.pauseRender()
        result("")
    }

    // MARK: - stop

    private func handleStop(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let textureId = validTextureId(from: arguments) else {
            result(NSNumber(value: -1))
            return
        }
        let render = renderMap[textureId]
        render?.stopRender()
        result("")
    }

    // MARK: - start

    private func handleStart(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let textureId = validTextureId(from: arguments) else {
            result(NSNumber(value: -1))
            return
        }
        let render = renderMap[textureId]
        render?.startRender()
        result("")
    }

    // MARK: - initPag

    private func handleInitPag(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              !(isNullOrNil(args[Arg.assetName]) && isNullOrNil(args[Arg.url]) && isNullOrNil(args[Arg.bytesData])) else {
            result(NSNumber(value: -1))
            NSLog("showPag arguments is nil")
            return
        }

        let initProgress = (args[Arg.initProgress] as? NSNumber)?.doubleValue ?? 0.0
        let repeatCount = (args[Arg.repeatCount] as? NSNumber)?.intValue ?? -1
        let autoPlay = (args[Arg.autoPlay] as? NSNumber)?.boolValue ?? false
        let reuse = (args[Arg.reuse] as? NSNumber)?.boolValue ?? false
        let reuseKey = args[Arg.reuseKey] as? String
        let viewId = (args[Arg.viewId] as? NSNumber)?.intValue ?? -1

        let videoEnabled: NSNumber? = args[Arg.videoEnabled] as? NSNumber
        let useDiskCache: NSNumber? = args[Arg.useDiskCache] as? NSNumber
        let cacheScale: NSNumber? = args[Arg.cacheScale] as? NSNumber
        let maxFrameRate: NSNumber? = args[Arg.maxFrameRate] as? NSNumber

        if isReuseEnabled && reuse {
            // 设置reuseKey 复用的render信息对象
            if let reuseKey = reuseKey, !reuseKey.isEmpty {
                let reuseItem = reuseMap[reuseKey]
                var existReuseRender = false
                if let reuseItem = reuseItem {
                    let reuseTextureId = reuseItem.getTextureId()
                    existReuseRender = reuseTextureId >= 0 && renderMap[reuseTextureId] != nil
                }

                if let reuseItem = reuseItem, existReuseRender {
                    reuseItem.usingViewSet.add(NSNumber(value: viewId))
                    result([Arg.textureId: reuseItem.getTextureId(),
                            Arg.width: reuseItem.getWidth(),
                            Arg.height: reuseItem.getHeight()] as [String: Any])
                    return
                } else if let reuseItem = reuseItem {
                    reuseItem.usingViewSet.add(NSNumber(value: viewId))
                    reuseItem.mutableResultsArray.append(result)
                    return
                } else {
                    let tempItem = ReuseItem()
                    tempItem.reuseKey = reuseKey
                    tempItem.usingViewSet.add(NSNumber(value: viewId))
                    reuseMap[reuseKey] = tempItem
                }
            }
        }

        // Asset source
        if let assetName = args[Arg.assetName] as? String, !assetName.isEmpty {
            var pagData = getCacheData(assetName)
            if pagData == nil {
                let package = args[Arg.package] as? String
                var resourcePath: String?
                if let package = package, !package.isEmpty {
                    resourcePath = registrar?.lookupKey(forAsset: assetName, fromPackage: package)
                } else {
                    resourcePath = registrar?.lookupKey(forAsset: assetName)
                }
                if let resourcePath = resourcePath {
                    let fullPath = Bundle.main.path(forResource: resourcePath, ofType: nil)
                    if let fullPath = fullPath {
                        pagData = try? Data(contentsOf: URL(fileURLWithPath: fullPath))
                    }
                }
                if let pagData = pagData {
                    setCacheData(assetName, data: pagData)
                }
            }
            if let pagData = pagData {
                pagRender(pagData: pagData, progress: initProgress, repeatCount: repeatCount,
                          autoPlay: autoPlay, videoEnabled: videoEnabled, useDiskCache: useDiskCache,
                          cacheScale: cacheScale, maxFrameRate: maxFrameRate, result: result,
                          reuse: reuse, reuseKey: reuseKey, viewId: viewId)
            } else {
                let flutterError = FlutterError(code: "-1100",
                                                message: "asset资源加载错误: \(assetName)", details: nil)
                result(flutterError)
                onInitPagError(reuse: reuse, reuseKey: reuseKey, flutterError: flutterError)
            }
        }

        // URL source
        if let url = args[Arg.url] as? String, !url.isEmpty {
            let pagData = getCacheData(url)
            if pagData == nil {
                weak var weakSelf = self
                TGFlutterPagDownloadManager.download(url) { data, _ in
                    if let data = data {
                        weakSelf?.setCacheData(url, data: data)
                        weakSelf?.pagRender(pagData: data, progress: initProgress,
                                            repeatCount: repeatCount, autoPlay: autoPlay,
                                            videoEnabled: videoEnabled, useDiskCache: useDiskCache,
                                            cacheScale: cacheScale, maxFrameRate: maxFrameRate,
                                            result: result, reuse: reuse, reuseKey: reuseKey,
                                            viewId: viewId)
                    } else {
                        let flutterError = FlutterError(code: "-1100",
                                                        message: "url资源加载错误: \(url)", details: nil)
                        result(flutterError)
                        weakSelf?.onInitPagError(reuse: reuse, reuseKey: reuseKey, flutterError: flutterError)
                    }
                }
            } else {
                pagRender(pagData: pagData!, progress: initProgress, repeatCount: repeatCount,
                          autoPlay: autoPlay, videoEnabled: videoEnabled, useDiskCache: useDiskCache,
                          cacheScale: cacheScale, maxFrameRate: maxFrameRate, result: result,
                          reuse: reuse, reuseKey: reuseKey, viewId: viewId)
            }
        }

        // Bytes source
        if let typedData = args[Arg.bytesData] as? FlutterStandardTypedData {
            pagRender(pagData: typedData.data, progress: initProgress, repeatCount: repeatCount,
                      autoPlay: autoPlay, videoEnabled: videoEnabled, useDiskCache: useDiskCache,
                      cacheScale: cacheScale, maxFrameRate: maxFrameRate, result: result,
                      reuse: reuse, reuseKey: reuseKey, viewId: viewId)
        }
    }

    // MARK: - enableCache

    private func handleEnableCache(_ arguments: Any?, result: @escaping FlutterResult) {
        var enable = true // 默认开启render cache
        if let args = arguments as? [String: Any],
           let enableValue = args[Arg.cacheEnabled] as? NSNumber {
            enable = enableValue.boolValue
        }
        enableRenderCache = enable
        result("")
    }

    // MARK: - setCacheSize

    private func handleSetCacheSize(_ arguments: Any?, result: @escaping FlutterResult) {
        var maxSize = 10
        if let args = arguments as? [String: Any],
           let sizeValue = args[Arg.cacheSize] as? NSNumber {
            maxSize = sizeValue.intValue
        }
        if maxSize >= 0 && maxSize <= Int(Int32.max) {
            maxFreePoolSize = maxSize
        } else {
            NSLog("Warning: Cache size out of int range, setting default value.")
            maxFreePoolSize = 10
        }
        result("")
    }

    // MARK: - enableMultiThread

    private func handleEnableMultiThread(_ arguments: Any?, result: @escaping FlutterResult) {
        var enable = true // 默认开启 MultiThread
        if let args = arguments as? [String: Any],
           let enableValue = args[Arg.multiThreadEnabled] as? NSNumber {
            enable = enableValue.boolValue
        }
        TGFlutterWorkerExecutor.sharedInstance.enableMultiThread = enable
        result("")
    }

    // MARK: - enableReuse

    private func handleEnableReuse(_ arguments: Any?, result: @escaping FlutterResult) {
        var enable = false // 默认关闭 enableReuse render 复用
        if let args = arguments as? [String: Any],
           let enableValue = args[Arg.reuseEnabled] as? NSNumber {
            enable = enableValue.boolValue
        }
        isReuseEnabled = enable
        result("")
    }

    // MARK: - Core Render

    private func pagRender(pagData: Data, progress: Double, repeatCount: Int,
                           autoPlay: Bool, videoEnabled: NSNumber?, useDiskCache: NSNumber?,
                           cacheScale: NSNumber?, maxFrameRate: NSNumber?,
                           result: @escaping FlutterResult, reuse: Bool,
                           reuseKey: String?, viewId: Int) {
        var textureId: Int64 = -1
        weak var weakSelf = self
        var render: TGFlutterPagRender

        if !enableRenderCache || freeEntryPool.isEmpty {
            render = TGFlutterPagRender()
            textureId = textures?.register(render) ?? -1
            render.textureId = textureId
            renderMap[textureId] = render
        } else {
            let cacheTextureId = getRenderCacheTextureId()
            textureId = cacheTextureId
            preFreeEntryPool.removeAll { $0 == cacheTextureId }
            freeEntryPool.removeAll { $0 == cacheTextureId }
            guard let cachedRender = renderMap[cacheTextureId] else {
                let flutterError = FlutterError(code: "-1101",
                                                message: "id异常，未命中缓存！", details: nil)
                result(flutterError)
                onInitPagError(reuse: reuse, reuseKey: reuseKey, flutterError: flutterError)
                return
            }
            render = cachedRender
        }

        let capturedTextureId = textureId
        let capturedRender = render

        // render异步并行setup异常时序处理
        TGFlutterWorkerExecutor.sharedInstance.post {
            capturedRender.setRepeatCount(repeatCount)
            capturedRender.setUp(pagData: pagData, progress: progress, frameUpdateCallback: {
                DispatchQueue.main.async {
                    weakSelf?.textures?.textureFrameAvailable(capturedTextureId)
                }
            }, eventCallback: { event in
                DispatchQueue.main.async {
                    weakSelf?.channel.invokeMethod(Callback.playCallback,
                                                   arguments: [Arg.textureId: capturedTextureId,
                                                               Arg.pagEvent: event] as [String: Any])
                }
            })

            DispatchQueue.main.async {
                if let videoEnabled = videoEnabled {
                    capturedRender.setVideoEnabled(videoEnabled.boolValue)
                }
                if let useDiskCache = useDiskCache {
                    capturedRender.setUseDiskCache(useDiskCache.boolValue)
                }
                if let cacheScale = cacheScale {
                    capturedRender.setCacheScale(cacheScale.floatValue)
                }
                if let maxFrameRate = maxFrameRate {
                    capturedRender.setMaxFrameRate(maxFrameRate.floatValue)
                }
                if autoPlay {
                    capturedRender.startRender()
                }

                result([Arg.textureId: capturedTextureId,
                        Arg.width: capturedRender.size.width,
                        Arg.height: capturedRender.size.height] as [String: Any])

                // 复用的render初始化完成 同步复用相同reuseKey result回调
                if let weakSelf = weakSelf, weakSelf.isReuseEnabled && reuse,
                   let reuseKey = reuseKey, !reuseKey.isEmpty {
                    if let reuseItem = weakSelf.reuseMap[reuseKey] {
                        reuseItem.setUp(textureId: capturedTextureId,
                                        width: Double(capturedRender.size.width),
                                        height: Double(capturedRender.size.height))
                        for pendingResult in reuseItem.mutableResultsArray {
                            pendingResult([Arg.textureId: capturedTextureId,
                                           Arg.width: capturedRender.size.width,
                                           Arg.height: capturedRender.size.height] as [String: Any])
                        }
                        reuseItem.mutableResultsArray.removeAll()
                    } else {
                        let tempItem = ReuseItem()
                        tempItem.usingViewSet.add(NSNumber(value: viewId))
                        weakSelf.reuseMap[reuseKey] = tempItem
                        tempItem.setUp(textureId: capturedTextureId,
                                       width: Double(capturedRender.size.width),
                                       height: Double(capturedRender.size.height))
                    }
                }
            }
        }
    }

    // MARK: - Error Handling

    private func onInitPagError(reuse: Bool, reuseKey: String?, flutterError: FlutterError) {
        guard isReuseEnabled && reuse, let reuseKey = reuseKey, !reuseKey.isEmpty else { return }
        if let reuseItem = reuseMap[reuseKey] {
            for pendingResult in reuseItem.mutableResultsArray {
                pendingResult(flutterError)
            }
            reuseItem.mutableResultsArray.removeAll()
        }
        reuseMap.removeValue(forKey: reuseKey)
    }

    // MARK: - Cache Helpers

    private func getRenderCacheTextureId() -> Int64 {
        guard !freeEntryPool.isEmpty else { return -1 }
        return freeEntryPool[0]
    }

    private func getCacheData(_ key: String) -> Data? {
        return cache.object(forKey: key as NSString) as Data?
    }

    private func setCacheData(_ key: String, data: Data) {
        cache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
    }

    // MARK: - Utilities

    private func isNullOrNil(_ value: Any?) -> Bool {
        return value == nil || value is NSNull
    }
}
