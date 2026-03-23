import Foundation

/// WorkThreadExecutor 是管理render缓存的队列单例类。
/// 提供全局并发队列和一个手动创建的串行队列
class TGFlutterWorkerExecutor {
    static let sharedInstance = TGFlutterWorkerExecutor()

    /// 并行队列开关
    var enableMultiThread: Bool = true

    private let concurrentQueue: DispatchQueue
    private let serialQueue: DispatchQueue

    private init() {
        concurrentQueue = DispatchQueue.global(qos: .default)
        serialQueue = DispatchQueue(label: "com.pag.serialQueue")
    }

    func post(_ task: @escaping () -> Void) {
        if enableMultiThread {
            concurrentQueue.async(execute: task)
        } else {
            serialQueue.async(execute: task)
        }
    }
}
