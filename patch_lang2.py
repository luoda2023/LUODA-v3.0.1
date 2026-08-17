# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding="utf-8")

add_cn = (
    '        ("Grant all at once", "\u4e00\u952e\u5168\u90e8\u6388\u6743"),\n'
    '        ("grant_all_tip", "\u4f9d\u6b21\u6253\u5f00\u7cfb\u7edf\u6388\u6743\u9875\u9762\uff0c\u8bf7\u6309\u63d0\u793a\u5141\u8bb8\u5404\u9879\u6743\u9650\uff0c\u5168\u90e8\u5b8c\u6210\u540e\u81ea\u52a8\u8fdb\u5165\u3002"),\n'
)
add_en = (
    '        ("Grant all at once", "Grant all at once"),\n'
    '        ("grant_all_tip", "System permission pages open one by one. Allow each one and the wizard finishes automatically."),\n'
)

def insert_after(path, anchor, addition):
    s = open(path, encoding="utf-8").read()
    idx = s.find(anchor)
    if idx < 0:
        print("MISS anchor in", path)
        raise SystemExit(1)
    nl = s.find("\n", idx) + 1
    s = s[:nl] + addition + s[nl:]
    open(path, "w", encoding="utf-8", newline="").write(s)
    print("OK", path)

insert_after(r"J:\codex-work\LUODA-v3.0.1\src\lang\cn.rs",
             '("Grant", "\u6388\u6743"),', add_cn)
insert_after(r"J:\codex-work\LUODA-v3.0.1\src\lang\en.rs",
             '("Grant", "Grant"),', add_en)
