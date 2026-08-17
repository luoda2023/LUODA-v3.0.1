# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding="utf-8")
add_en = (
    '        ("Grant all at once", "Grant all at once"),\n'
    '        ("grant_all_tip", "System permission pages open one by one. Allow each one and the wizard finishes automatically."),\n'
)
p = r"J:\codex-work\LUODA-v3.0.1\src\lang\en.rs"
s = open(p, encoding="utf-8").read()
anchor = '("File Transfer Assistant", "File Transfer Assistant"),'
idx = s.find(anchor)
if idx < 0:
    print("MISS anchor"); raise SystemExit(1)
nl = s.find("\n", idx) + 1
s = s[:nl] + add_en + s[nl:]
open(p, "w", encoding="utf-8", newline="").write(s)
print("OK en.rs")
cn = open(r"J:\codex-work\LUODA-v3.0.1\src\lang\cn.rs", encoding="utf-8").read()
i = cn.find('("Grant all at once"')
print(repr(cn[i-4:i+120]))
