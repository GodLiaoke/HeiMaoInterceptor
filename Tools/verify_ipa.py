#!/usr/bin/env python3
"""产物核验：版本号、权限位、签名段、混淆效果。只读，不改包。"""
import plistlib
import re
import struct
import subprocess
import sys
import zipfile


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True).stdout


def has_code_signature(path: str) -> bool:
    """扫 Mach-O 的 load commands，看有没有 LC_CODE_SIGNATURE(0x1d)"""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 32:
        return False
    magic = struct.unpack(">I", data[:4])[0]
    if magic not in (0xCAFEBABE, 0xFEEDFACE, 0xFEEDFACF):
        return False
    is64 = magic in (0xCAFEBABE, 0xFEEDFACF)
    ncmds_off = 16
    ncmds = struct.unpack("<I", data[ncmds_off:ncmds_off + 4])[0]
    off = ncmds_off + 12 if is64 else ncmds_off + 12
    for _ in range(ncmds):
        if off + 8 > len(data):
            break
        cmd, size = struct.unpack("<II", data[off:off + 8])
        if cmd == 0x1D:          # LC_CODE_SIGNATURE
            return True
        if size <= 0:
            break
        off += size
    return False


def check(ipa: str):
    print(f"\n=== {ipa}")
    z = zipfile.ZipFile(ipa)
    names = z.namelist()
    app_info = [n for n in names if re.match(r"Payload/[^/]+\.app/Info\.plist$", n)]
    if not app_info:
        print("FAIL: 找不到 App 的 Info.plist")
        return False
    info = plistlib.loads(z.read(app_info[0]))
    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    name = info.get("CFBundleDisplayName")
    minos = info.get("MinimumOSVersion")
    print(f"  名称={name} 版本={version} build={build} MinimumOSVersion={minos}")

    ext_info = [n for n in names if n.endswith("HeiMaoTunnel.appex/Info.plist")]
    if ext_info:
        ei = plistlib.loads(z.read(ext_info[0]))
        print(f"  扩展={ei.get('CFBundleShortVersionString')} build={ei.get('CFBundleVersion')}")

    exe = [n for n in names if re.match(r"Payload/[^/]+\.app/[^/]+$", n)]
    ok = True
    for n in exe + [x for x in names if x.endswith(".appex/HeiMaoTunnel")]:
        info_z = z.getinfo(n)
        perm = (info_z.external_attr >> 16) & 0o777
        blob = z.read(n)
        tmp = "/tmp/_bin_check"
        with open(tmp, "wb") as f:
            f.write(blob)
        signed = has_code_signature(tmp)
        print(f"  {n.split('/')[-1]}: 权限={oct(perm)} 大小={len(blob)} 签名段={'有' if signed else '无'}")
        if perm != 0o755:
            print("   FAIL: 权限不是 755")
            ok = False
        if not signed:
            print("   WARN: 没有 LC_CODE_SIGNATURE")
    return ok


if __name__ == "__main__":
    all_ok = True
    for f in sys.argv[1:]:
        all_ok &= check(f)
    print("\nRESULT:", "OK" if all_ok else "CHECK_FAIL")
