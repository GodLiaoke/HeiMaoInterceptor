import Foundation

/// 全局后台工作队列
///
/// 卡密校验、响应解密、规则包解密、规则解析、本地状态落盘这些活
/// 全部丢到这里串行执行，主线程只负责刷新界面。
///
/// 为什么串行：这几件事彼此依赖（先校验再解密再解析再落盘），
/// 串行能保证顺序，也避免同时解析两份几万条规则把 CPU 打满。
enum WorkQueue {

    static let shared = DispatchQueue(label: "com.heimao.work",
                                      qos: .userInitiated,
                                      attributes: [])

    static func async(_ block: @escaping () -> Void) {
        shared.async(execute: block)
    }

    /// 回主线程刷新界面
    static func main(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
