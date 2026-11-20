#!/usr/bin/env python3
"""打包前复核：看门狗里写的哈希必须等于主程序当前的 __TEXT 哈希。

任何一步挪动了主程序（例如有人把 seal 步骤放到了签名之后），这里会拦下来。
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import seal_binaries as sb  # noqa: E402


def main():
    app = sys.argv[1].rstrip("/")
    app_bin = app + "/HeiMaoInterceptor"
    kit_bin = app + "/Frameworks/HMKit.framework/HMKit"

    digest = sb.text_sha256(app_bin)
    if not digest:
        print("SEAL_VERIFY: FAIL 读不到主程序 __text")
        return 1

    with open(kit_bin, "rb") as f:
        data = f.read()
    mark = b"HMTEXTAPP:"
    i = data.find(mark)
    if i < 0:
        print("SEAL_VERIFY: FAIL 看门狗里没有占位符")
        return 1
    val = data[i + len(mark):i + len(mark) + 64].decode("ascii", "replace")
    if val != digest:
        print("SEAL_VERIFY: FAIL %s != %s" % (val[:16], digest[:16]))
        return 1

    # 结构标记必须在（主程序启动时会查这个，缺了就判篡改直接退出）
    if b"HMTEXTAPP:" not in data:
        print("SEAL_VERIFY: FAIL 看门狗里没有结构标记 HMTEXTAPP:")
        return 1
    if b"HMKITSZ:" not in open(app_bin, "rb").read():
        print("SEAL_VERIFY: FAIL 主程序里没有框架标记 HMKITSZ:")
        return 1

    size = sb.text_slice(kit_bin)
    if not size:
        print("SEAL_VERIFY: FAIL 读不到看门狗 __TEXT")
        return 1

    print("SEAL_VERIFY: OK app=%s kit_text=%d" % (digest[:16], size[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
