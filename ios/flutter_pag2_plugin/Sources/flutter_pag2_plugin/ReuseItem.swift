import Foundation
import Flutter

/// 复用render info类
class ReuseItem {
    /// 自身reuseKey pag资源路径
    var reuseKey: String?
    /// 相同reuseKey的pagView端viewId 包括自身，生命周期同textureId的render
    var usingViewSet: NSMutableSet
    /// 相同reuseKey的pagView端viewId initPag method的FlutterResult 不包括自身
    var mutableResultsArray: [FlutterResult]

    /// 自身纹理id
    private var textureId: Int64
    /// pag data 宽
    private var width: Double
    /// pag data 高
    private var height: Double

    init() {
        textureId = -1
        usingViewSet = NSMutableSet()
        width = 0
        height = 0
        reuseKey = nil
        mutableResultsArray = []
    }

    func setUp(textureId: Int64, width: Double, height: Double) {
        self.textureId = textureId
        self.width = width
        self.height = height
    }

    func getTextureId() -> Int64 {
        return textureId
    }

    func getWidth() -> Double {
        return width
    }

    func getHeight() -> Double {
        return height
    }

    var description: String {
        return "ReuseItem{textureId=\(textureId), usingViewSetNum=\(usingViewSet.count), width=\(Int(width)), height=\(Int(height))}"
    }
}
