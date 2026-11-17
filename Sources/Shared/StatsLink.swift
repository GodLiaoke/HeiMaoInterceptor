import Foundation
import Darwin

/// 扩展 → 主程序 的统计直连通道（本机回环 TCP）
///
/// 为什么要它：`sendProviderMessage` 在两种情况下会静默失效 ——
/// 隧道刚重连（reassert）的那几秒，以及伪签名环境（巨魔 / 侧载）下
/// 扩展与主程序的应用组容器对不上；落盘共享目录同样依赖沙箱放行。
/// 三条通道里只要有一条被环境挡住，面板就永远是 0，而拦截本身完全正常。
///
/// 回环 TCP 不吃这些：扩展在自己的进程里 listen 一个只有本机能连的端口，
/// 主程序直接连上去问数字。不经过沙箱共享目录、不走消息回调、不受签名影响。
enum StatsLink {

    /// 只有本机回环能连：绑定地址固定 127.0.0.1，外部不可达。
    /// 给三个候选端口：万一上一轮扩展进程还没完全退出、端口被占住，
    /// 自动用下一个，主程序这边也按同样顺序找。
    static let candidatePorts: [UInt16] = [47831, 47832, 47833]

    /// 请求行：带个前缀，避免误连到别的服务上乱读
    static let requestLine = "HMSTATS\n"

    /// 主程序侧：问一次统计，拿不到就回空字典（调用方再走别的通道）
    static func fetch(timeout: TimeInterval = 1.2) -> [String: Any] {
        for p in candidatePorts {
            let obj = fetch(port: p, timeout: timeout)
            if !obj.isEmpty { return obj }
        }
        return [:]
    }

    static func fetch(port: UInt16, timeout: TimeInterval) -> [String: Any] {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return [:] }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        /* 非阻塞 connect + poll：扩展没起来的时候是立刻 ECONNREFUSED，
           万一扩展卡住也不能把主线程吊在这里。 */
        let originalFlags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK)

        let rc = withUnsafePointer(to: &addr) { raw -> Int32 in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if rc != 0 {
            guard errno == EINPROGRESS else { return [:] }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&pfd, 1, Int32(max(timeout, 0.2) * 1000)) > 0 else { return [:] }
            var soErr: Int32 = 0
            var errLen = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &errLen) == 0, soErr == 0 else {
                return [:]
            }
        }

        _ = fcntl(fd, F_SETFL, originalFlags)

        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let req = Array(requestLine.utf8)
        _ = req.withUnsafeBufferPointer { buf -> Int in
            guard let base = buf.baseAddress else { return 0 }
            return send(fd, UnsafeRawPointer(base), buf.count, 0)
        }

        var out = Data()
        var chunk = [UInt8](repeating: 0, count: 16384)
        while out.count < 256 * 1024 {
            let got = chunk.withUnsafeMutableBufferPointer { buf -> Int in
                guard let base = buf.baseAddress else { return 0 }
                return recv(fd, UnsafeMutableRawPointer(base), buf.count, 0)
            }
            if got <= 0 { break }
            out.append(contentsOf: chunk[0..<got])
        }

        guard !out.isEmpty,
              let any = try? JSONSerialization.jsonObject(with: out),
              let obj = any as? [String: Any] else { return [:] }
        return obj
    }

    /// 扩展侧：绑定地址用回环，绝不对外
    static func loopbackAddress(port: UInt16) -> sockaddr_in {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return addr
    }
}
