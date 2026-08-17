# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding="utf-8")

add_keys = (
    '        ("Email", "\u90ae\u7bb1"),\n'
    '        ("Wayland", "Wayland"),\n'
    '        ("Switch Windows session", "\u5207\u6362 Windows \u4f1a\u8bdd"),\n'
    '        ("VIP", "VIP \u4f1a\u5458"),\n'
)
add_keys_en = (
    '        ("Email", "Email"),\n'
    '        ("Wayland", "Wayland"),\n'
    '        ("Switch Windows session", "Switch Windows session"),\n'
    '        ("VIP", "VIP"),\n'
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
             '("File Transfer Assistant", "\u6587\u4ef6\u4f20\u8f93\u52a9\u624b"),', add_keys)
insert_after(r"J:\codex-work\LUODA-v3.0.1\src\lang\en.rs",
             '("File Transfer Assistant", "File Transfer Assistant"),', add_keys_en)
t = open(r"J:\codex-work\LUODA-v3.0.1\src\lang\template.rs", encoding="utf-8").read()
if '"File Transfer Assistant"' in t:
    insert_after(r"J:\codex-work\LUODA-v3.0.1\src\lang\template.rs",
                 '"File Transfer Assistant"', add_keys_en)
else:
    print("template.rs no anchor; skipped")
