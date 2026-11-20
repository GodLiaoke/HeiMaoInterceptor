#!/usr/bin/env python3
"""算出 ipa 里主程序 `__TEXT,__text` 的 SHA-256（代码段指纹）。

为什么发版要单独算这个：
  整包 SHA-256 会被重签改写（巨魔 / ESign / 爱思 都会重写签名段），
  用户重签之后就永远对不上。代码段指纹只覆盖指令区，重签不变、改代码必变，
  App 内「设置 → 关于 → 代码指纹」显示的就是它。

用法：
  python3 Tools/code_hash.py 某个.ipa [main|tunnel]
"""
import hashlib
import struct
import sys
import zipfile


def section_slice(data, seg_name, sect_name):
    if len(data) < 32:
        return None
    magic, = struct.unpack_from("<I", data, 0)
    if magic != 0xFEEDFACF:
        return None
    ncmds, sizeofcmds = struct.unpack_from("<II", data, 16)
    body = data[32:32 + sizeofcmds]
    p = 0
    for _ in range(ncmds):
        if p + 8 > len(body):
            break
        cmd, cmdsize = struct.unpack_from("<II", body, p)
        if cmdsize < 8 or p + cmdsize > len(body):
            break
        if cmd == 0x19 and cmdsize >= 72:                       # LC_SEGMENT_64
            seg = body[p + 8:p + 24].rstrip(b"\0").decode("utf-8", "replace")
            nsects, = struct.unpack_from("<I", body, p + 64)
            q = p + 72
            for _ in range(nsects):
                if q + 80 > len(body) or q + 80 > p + cmdsize:
                    break
                sect = body[q:q + 16].rstrip(b"\0").decode("utf-8", "replace")
                if seg == seg_name and sect == sect_name:
                    size, = struct.unpack_from("<Q", body, q + 40)
                    off, = struct.unpack_from("<I", body, q + 48)
                    return off, size
                q += 80
        p += cmdsize
    return None


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    ipa = sys.argv[1]
    which = sys.argv[2] if len(sys.argv) > 2 else "main"
    app = "Payload/HeiMaoInterceptor.app/HeiMaoInterceptor"
    if which == "tunnel":
        app = "Payload/HeiMaoInterceptor.app/PlugIns/HeiMaoTunnel.appex/HeiMaoTunnel"
    with zipfile.ZipFile(ipa) as z:
        names = [n for n in z.namelist() if n.endswith(app)]
        if not names:
            print("ERROR: 包里找不到 %s" % app)
            return 1
        data = z.read(names[0])
    sl = section_slice(data, "__TEXT", "__text")
    if not sl:
        print("ERROR: 解析 __TEXT,__text 失败")
        return 1
    off, size = sl
    print(hashlib.sha256(data[off:off + size]).hexdigest())
    return 0


if __name__ == "__main__":
    sys.exit(main())
