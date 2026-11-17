import Foundation
import Darwin

/// 扩展里的统计小服务（只监听 127.0.0.1）
///
/// 一次只有一个客户端（主程序），请求发一个 "HMSTATS\n" 就回一份 JSON。
/// 不留长连接、不占端口之外的东西，主程序拿完数字立刻断开。
///
/// 为什么不用高层 API：Network.framework 的 listener 在扩展里要处理一堆
/// 状态回调，出错还看不出来；裸 socket 几行就够，失败也能一眼看到 errno。
final class StatsServer {

    private let ports: [UInt16]
    private let snapshot: () -> [String: Any]

    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var running = false

    private let queue = DispatchQueue(label: "com.heimao.stats.server", qos: .utility)

    init(ports: [UInt16] = StatsLink.candidatePorts,
         snapshot: @escaping () -> [String: Any]) {
        self.ports = ports
        self.snapshot = snapshot
    }

    // MARK: - 生命周期

    func start() {
        lock.lock()
        if running { lock.unlock(); return }
        running = true
        lock.unlock()
        queue.async { [weak self] in self?.run() }
    }

    func stop() {
        /* 只改标志，监听口由监听线程自己关：
           在另一个线程 close 会跟 accept/poll 抢同一个 fd 号，容易误关别人。 */
        lock.lock()
        running = false
        lock.unlock()
    }

    // MARK: - 监听

    /// 按候选端口顺序尝试绑定，第一个成功的用作监听口
    private func bindAny() -> Int32? {
        for p in ports {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }

            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes,
                       socklen_t(MemoryLayout<Int32>.size))

            var addr = StatsLink.loopbackAddress(port: p)
            let bindResult = withUnsafePointer(to: &addr) { raw -> Int32 in
                raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bindResult == 0, listen(fd, 8) == 0 {
                return fd
            }
            close(fd)
        }
        return nil
    }

    private func run() {
        guard let fd = bindAny() else { return }

        /* 非阻塞 + poll 轮询：这样停的时候不用从别的线程关监听口 */
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        lock.lock()
        listenFD = fd
        lock.unlock()

        while isRunning {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, 500)
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            if ready == 0 { continue }
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }
            serve(client)
        }

        lock.lock()
        listenFD = -1
        lock.unlock()
        close(fd)
    }

    private var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    // MARK: - 应答

    private func serve(_ fd: Int32) {
        defer { close(fd) }

        /* accept 出来的 fd 在部分系统上会继承非阻塞，改回阻塞 + 收超时 */
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)

        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        /* 请求内容不影响结果，只要连上来就是要统计；读一下把请求行吃掉 */
        var req = [UInt8](repeating: 0, count: 64)
        _ = req.withUnsafeMutableBufferPointer { buf -> Int in
            guard let base = buf.baseAddress else { return 0 }
            return recv(fd, UnsafeMutableRawPointer(base), buf.count, 0)
        }

        var payload = snapshot()
        if payload.isEmpty { return }
        payload["bridgeAt"] = Int(Date().timeIntervalSince1970)
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = send(fd, base.advanced(by: sent), data.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }
}
