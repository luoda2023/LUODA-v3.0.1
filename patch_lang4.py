# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding="utf-8")

add_cn = (
    '        ("Stop receiving", "\u4e0d\u518d\u63a5\u6536"),\n'
    '        ("blocked_receive_tip", "\u5df2\u505c\u6b62\u63a5\u6536\u8be5\u8bbe\u5907\u7684\u6d88\u606f"),\n'
    '        ("unblocked_receive_tip", "\u5df2\u6062\u590d\u63a5\u6536\u8be5\u8bbe\u5907\u7684\u6d88\u606f"),\n'
    '        ("bt_dotchat_hint", "\u4ec5\u53ef\u8fde\u63a5\u5df2\u5b89\u88c5\u201c\u70b9\u804a\u201d\u7684\u8bbe\u5907\uff0c\u5176\u5b83\u84dd\u7259\u8bbe\u5907\u65e0\u6cd5\u8fde\u63a5\u804a\u5929\u3002"),\n'
)
add_en = (
    '        ("Stop receiving", "Stop receiving"),\n'
    '        ("blocked_receive_tip", "Stopped receiving messages from this device"),\n'
    '        ("unblocked_receive_tip", "Resumed receiving messages from this device"),\n'
    '        ("bt_dotchat_hint", "Only devices with DotChat installed can be connected. Other Bluetooth devices cannot chat."),\n'
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
             '("Unblock", "\u53d6\u6d88\u5c4f\u853d"),', add_cn)
insert_after(r"J:\codex-work\LUODA-v3.0.1\src\lang\en.rs",
             '("File Transfer Assistant", "File Transfer Assistant"),', add_en)
