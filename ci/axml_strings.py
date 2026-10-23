#!/usr/bin/env python3
"""从 Android 二进制清单（AXML，即 APK 里的 AndroidManifest.xml）里解出字符串池。

为什么不用 `strings`：
APK 内的 AndroidManifest.xml 是 aapt2 编译出的二进制 AXML，字符串池**不是**连续
的可打印 ASCII（本工程实测 `strings` 对它的命中数为 0）。因此
`strings am.bin | grep xxx` 这种断言无论清单里有没有那个字符串都会「没查到」——
既可能假失败、也可能假通过，不能用它做构建期校验。本脚本按 AXML 格式真正解析字符串池。

用法：
    python3 ci/axml_strings.py <AndroidManifest.xml>            # 逐行打印全部字符串
    python3 ci/axml_strings.py <AndroidManifest.xml> 关键词...  # 全部命中才 exit 0

退出码：0=全部关键词命中；1=有缺失（缺失项打到 stderr）。
"""

import struct
import sys


def _read_string_pool(buf, off):
    """off 指向 RES_STRING_POOL_TYPE 块起始，返回字符串列表。"""
    _t, _hs, _sz = struct.unpack_from("<HHI", buf, off)
    body = off + 8
    scount, _styc, flags, sstart, _stystart = struct.unpack_from("<IIIII", buf, body)
    utf8 = bool(flags & 0x00000100)
    offsets = struct.unpack_from("<%dI" % scount, buf, body + 20)
    base = off + sstart
    out = []
    for o in offsets:
        p = base + o
        if utf8:
            # UTF-8 池：u8/u16 变长「字符数」+ u8/u16 变长「字节数」+ UTF-8 数据 + 0x00
            clen, p = _uleb_utf8(buf, p)
            blen, p = _uleb_utf8(buf, p)
            out.append(buf[p:p + blen].decode("utf-8", "replace"))
        else:
            # UTF-16 池：u16「码元数」+ UTF-16LE 数据 + 0x0000 结尾
            clen = struct.unpack_from("<H", buf, p)[0]
            p += 2
            out.append(buf[p:p + clen * 2].decode("utf-16-le", "replace"))
    return out


def _uleb_utf8(buf, p):
    """AXML UTF-8 池的长度前缀：1 或 2 字节（最高位标记续字节）。"""
    x = buf[p]
    if x & 0x80:
        return ((x & 0x7F) << 8) | buf[p + 1], p + 2
    return x, p + 1


def axml_strings(path):
    buf = open(path, "rb").read()
    if struct.unpack_from("<H", buf, 0)[0] != 0x0003:
        raise SystemExit("不是二进制 AXML（RES_XML 头不匹配）：%s" % path)
    hsize = struct.unpack_from("<H", buf, 2)[0]
    off = hsize
    while off + 8 <= len(buf):
        t, _hs, sz = struct.unpack_from("<HHI", buf, off)
        if sz == 0:
            break
        if t == 0x0001:
            return _read_string_pool(buf, off)
        off += sz
    raise SystemExit("未找到字符串池：%s" % path)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    strings = axml_strings(argv[1])
    if len(argv) == 2:
        for s in strings:
            print(s)
        return 0
    wanted = argv[2:]
    missing = [w for w in wanted if not any(w in s for s in strings)]
    for w in wanted:
        print(("OK   " if w not in missing else "MISS ") + w)
    if missing:
        print("::error::清单缺少: " + ", ".join(missing), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))