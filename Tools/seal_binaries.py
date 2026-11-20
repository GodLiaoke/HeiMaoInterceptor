#!/usr/bin/env python3
"""把构建期才知道的两个值写进二进制（1.2.4 看门狗互校验）。

要看门狗（HMKit）校验主程序，就得在**编译之后**把它算出来再写回去。
两个占位符必须等长替换，否则会破坏 Mach-O 结构：

  主程序里的  HMKITSZ:00000000       -> HMKITSZ:<HMKit __TEXT 字节数>
  看门狗里的  HMTEXTAPP:000...0(64)  -> HMTEXTAPP:<主程序 __TEXT 段的 SHA-256>

顺序不能反：
  1. 先写主程序里的框架大小（这一步会改主程序 __TEXT 的内容）
  2. 再算主程序 __TEXT 的哈希（此时内容已定稿）
  3. 最后把哈希写进看门狗（改的是框架，不影响主程序）

签名放在后面做：codesign / ldid 只动 __LINKEDIT，不改 __TEXT，
所以签名之后的哈希和现在算出来的完全一致。

用法：
  python3 Tools/seal_binaries.py <App.app 路径>
"""
import hashlib
import struct
import sys

APP_MARKS = ["HMKITSZ:", "HMTEXTAPP:"]


def text_slice(path):
    with open(path, "rb") as f:
        head = f.read(32)
        if len(head) < 32:
            return None
        magic, = struct.unpack_from("<I", head, 0)
        if magic != 0xFEEDFACF:
            return None
        ncmds, sizeofcmds = struct.unpack_from("<II", head, 16)
        f.seek(32)
        body = f.read(sizeofcmds)
    p = 0
    for _ in range(ncmds):
        if p + 8 > len(body):
            break
        cmd, cmdsize = struct.unpack_from("<II", body, p)
        if cmdsize < 8 or p + cmdsize > len(body):
            break
        if cmd == 0x19 and cmdsize >= 72:                      # LC_SEGMENT_64
            name = body[p + 8:p + 24].rstrip(b"\0").decode("utf-8", "replace")
            if name == "__TEXT":
                fileoff, filesize = struct.unpack_from("<QQ", body, p + 40)
                return fileoff, filesize
        p += cmdsize
    return None


def text_sha256(path):
    sl = text_slice(path)
    if not sl:
        return None
    off, size = sl
    h = hashlib.sha256()
    left = size
    with open(path, "rb") as f:
        f.seek(off)
        while left > 0:
            chunk = f.read(min(left, 1 << 18))
            if not chunk:
                return None
            h.update(chunk)
            left -= len(chunk)
    return h.hexdigest()


def patch(path, mark, width, value):
    if len(value) != width:
        raise SystemExit("SEAL_FAIL: 替换值长度不对 %s %r" % (mark, value))
    with open(path, "rb") as f:
        data = f.read()
    needle = mark.encode() + b"0" * width
    n = data.count(needle)
    if n != 1:
        raise SystemExit("SEAL_FAIL: %s 占位符命中 %d 次（必须恰好 1 次）" % (mark, n))
    idx = data.find(needle)
    data = data[:idx] + mark.encode() + value.encode() + data[idx + len(needle):]
    with open(path, "wb") as f:
        f.write(data)
    print("SEAL: %s <- %s" % (mark, value))


def main():
    if len(sys.argv) < 2:
        raise SystemExit("用法: seal_binaries.py <App.app>")
    app = sys.argv[1].rstrip("/")
    main_bin = app + "/HeiMaoInterceptor"
    kit_bin = app + "/Frameworks/HMKit.framework/HMKit"

    for p in (main_bin, kit_bin):
        sl = text_slice(p)
        if not sl:
            raise SystemExit("SEAL_FAIL: 读不到 __TEXT 段 %s" % p)
        print("TEXT: %s off=%d size=%d" % (p.split("/")[-1], sl[0], sl[1]))

    kit_size = text_slice(kit_bin)[1]
    # 1) 框架大小写进主程序（等长 8 位十进制）
    patch(main_bin, "HMKITSZ:", 8, str(kit_size).zfill(8))  # 等长：不足 8 位补零

    # 2) 主程序定稿后算哈希
    digest = text_sha256(main_bin)
    if not digest or len(digest) != 64:
        raise SystemExit("SEAL_FAIL: 主程序 __TEXT 哈希算不出来")
    print("APP_TEXT_SHA256: %s" % digest)

    # 3) 哈希写进看门狗
    patch(kit_bin, "HMTEXTAPP:", 64, digest)

    # 4) 复核：算一次哈希，必须和写进看门狗的一致
    again = text_sha256(main_bin)
    if again != digest:
        raise SystemExit("SEAL_FAIL: 复核哈希不一致")
    print("SEAL_OK app=%s kit_text=%d" % (digest[:16], kit_size))


if __name__ == "__main__":
    main()
