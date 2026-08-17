# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding="utf-8")

def patch_file(path, replacements):
    s = open(path, encoding="utf-8").read()
    for old, new in replacements:
        cnt = s.count(old)
        if cnt == 0:
            print("MISS in", path, repr(old[:80]))
            raise SystemExit(1)
        if cnt > 1:
            print("AMBIG in", path, repr(old[:80]), "x", cnt)
            raise SystemExit(1)
        s = s.replace(old, new)
    open(path, "w", encoding="utf-8", newline="").write(s)
    print("OK", path)

p = r"J:\codex-work\LUODA-v3.0.1\flutter\lib\mobile\pages\bt_chat_page.dart"
patch_file(p, [
    # 1. add _toggleBlock method after _disconnect
    ("""  void _disconnect() {
    final active = _active;
    if (active == null) return;
    unawaited(_bt.disconnect(active.mac));
    setState(() => _active = null);
  }
""",
     """  void _disconnect() {
    final active = _active;
    if (active == null) return;
    unawaited(_bt.disconnect(active.mac));
    setState(() => _active = null);
  }

  /// Block or unblock a Bluetooth peer. Blocking stops incoming messages
  /// and drops the active link immediately.
  void _toggleBlock(BtDevice device) {
    final wasBlocked = gFFI.chatSettingsModel.isBlocked(device.peerId);
    gFFI.chatSettingsModel.toggleBlocked(device.peerId);
    if (!wasBlocked) {
      unawaited(_bt.disconnect(device.mac));
      if (mounted) setState(() => _active = null);
      showToast(translate('blocked_receive_tip'));
    } else {
      showToast(translate('unblocked_receive_tip'));
    }
  }
"""),
    # 2. add block button in conversation header, before Disconnect
    ("""              TextButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: Text(translate('Disconnect')),
              ),
""",
     """              IconButton(
                onPressed: () => _toggleBlock(active),
                tooltip: gFFI.chatSettingsModel.isBlocked(active.peerId)
                    ? translate('Unblock')
                    : translate('Stop receiving'),
                icon: Icon(
                  gFFI.chatSettingsModel.isBlocked(active.peerId)
                      ? Icons.block_rounded
                      : Icons.volume_off_rounded,
                  size: 20,
                  color: gFFI.chatSettingsModel.isBlocked(active.peerId)
                      ? Colors.redAccent
                      : Colors.grey,
                ),
              ),
              TextButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: Text(translate('Disconnect')),
              ),
"""),
    # 3. hint in scan section empty state
    ("""      child: _found.isEmpty && !_scanning
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                translate('Tap Scan to find Bluetooth devices around you.'),
                style: TextStyle(
                  fontSize: MobileText.bodySm,
                  color: dark
                      ? MyTheme.mutedDark
                      : MyTheme.mutedLight,
                ),
              ),
            )
""",
     """      child: _found.isEmpty && !_scanning
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    translate('Tap Scan to find Bluetooth devices around you.'),
                    style: TextStyle(
                      fontSize: MobileText.bodySm,
                      color: dark
                          ? MyTheme.mutedDark
                          : MyTheme.mutedLight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    translate('bt_dotchat_hint'),
                    style: TextStyle(
                      fontSize: MobileText.captionSm,
                      color: dark
                          ? MyTheme.mutedDark
                          : MyTheme.mutedLight,
                    ),
                  ),
                ],
              ),
            )
"""),
])
