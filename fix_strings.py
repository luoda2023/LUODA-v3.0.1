# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding="utf-8")
p = r"J:\codex-work\LUODA-v3.0.1\flutter\android\app\src\main\res\values\strings.xml"
s = open(p, encoding="utf-8").read()
print("BEFORE:")
print(s)
label = "\u70b9\u804a\u8f93\u5165"  # 点聊输入
desc = "\u8fdc\u7a0b\u534f\u52a9\u4f1a\u8bdd\u8fdb\u884c\u65f6\uff0c\u5141\u8bb8\u53d7\u4fe1\u4efb\u7684\u8bbe\u5907\u63a7\u5236\u8fd9\u53f0\u624b\u673a"
lines = []
for ln in s.splitlines():
    if "accessibility_service_description" in ln and "?" in ln:
        ln = '    <string name="accessibility_service_description">' + desc + '</string>'
    if "accessibility_service_label" in ln and "?" in ln:
        ln = '    <string name="accessibility_service_label">' + label + '</string>'
    lines.append(ln)
out = "\n".join(lines) + "\n"
open(p, "w", encoding="utf-8", newline="").write(out)
print("AFTER:")
print(open(p, encoding="utf-8").read())
