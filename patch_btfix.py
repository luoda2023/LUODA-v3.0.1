# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding="utf-8")
p = r"J:\codex-work\LUODA-v3.0.1\flutter\lib\mobile\pages\bt_chat_page.dart"
s = open(p, encoding="utf-8").read()
old = """  void _toggleBlock(BtDevice device) {
    final wasBlocked = gFFI.chatSettingsModel.isBlocked(device.peerId);
    gFFI.chatSettingsModel.toggleBlocked(device.peerId);
    if (!wasBlocked) {"""
new = """  void _toggleBlock(BtDevice device) {
    final wasBlocked = gFFI.chatSettingsModel.isBlocked(device.peerId);
    unawaited(gFFI.chatSettingsModel.toggleBlock(device.peerId));
    if (!wasBlocked) {"""
assert s.count(old) == 1
open(p, "w", encoding="utf-8", newline="").write(s.replace(old, new))
print("OK")
