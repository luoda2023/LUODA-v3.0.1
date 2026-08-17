# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding="utf-8")
p = r"J:\codex-work\LUODA-v3.0.1\flutter\android\app\src\main\kotlin\com\luoda\remote\BluetoothService.kt"
lines = open(p, encoding="utf-8").read().splitlines(keepends=True)

def repl(n, new):
    # n is 1-based; keep original indentation
    indent = lines[n-1][:len(lines[n-1]) - len(lines[n-1].lstrip())]
    lines[n-1] = indent + new + "\n"

# \u escape-free Chinese written via escapes below
repl(164, 'postToDart("error", mapOf("message" to "\u65e0\u6cd5\u5f00\u542f\u84dd\u7259: ${e.message}"))')
repl(179, 'postToDart("error", mapOf("message" to "\u8bfb\u53d6\u5df2\u914d\u5bf9\u8bbe\u5907\u5931\u8d25\uff0c\u8bf7\u68c0\u67e5\u84dd\u7259\u8fde\u63a5\u6743\u9650"))')
repl(186, 'postToDart("error", mapOf("message" to "\u6b64\u8bbe\u5907\u4e0d\u652f\u6301\u84dd\u7259"))')
repl(241, 'postToDart("error", mapOf("message" to "\u5f00\u59cb\u626b\u63cf\u5931\u8d25\uff0c\u8bf7\u68c0\u67e5\u84dd\u7259\u626b\u63cf\u6743\u9650"))')
repl(243, 'postToDart("error", mapOf("message" to "\u5f00\u59cb\u626b\u63cf\u5931\u8d25: ${e.message}"))')
repl(313, 'postToDart("error", mapOf("message" to "\u6b64\u8bbe\u5907\u4e0d\u652f\u6301\u84dd\u7259"))')
repl(317, 'postToDart("error", mapOf("message" to "\u84dd\u7259\u672a\u5f00\u542f"))')
repl(337, 'postToDart("error", mapOf("message" to "\u8fde\u63a5\u5931\u8d25\uff0c\u8bf7\u68c0\u67e5\u84dd\u7259\u8fde\u63a5\u6743\u9650"))')
repl(340, 'postToDart("error", mapOf("message" to "\u8fde\u63a5\u5931\u8d25: ${e.message}"))')

open(p, "w", encoding="utf-8", newline="").write("".join(lines))
# verify
out = open(p, encoding="utf-8").read()
import re
left = re.findall(r'"[?]{2,}[^"]*"', out)
print("remaining ?-strings:", left)
print("OK")
