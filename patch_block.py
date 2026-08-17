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

# 1. chat_model.dart: enforce block on receive
patch_file(r"J:\codex-work\LUODA-v3.0.1\flutter\lib\models\chat_model.dart", [
    ("""    final wasIpSource =
        DirectPairingStore.extractDirectEndpoint(peerId).isNotEmpty;
    peerId = DirectPairingStore.canonicalConversationId(peerId);
    _touchChatActivity(peerId);

    final messagekey = MessageKey(peerId, id);
    if (envelope != null && envelope.type != 'message') {
      await _handleEnvelope(messagekey, envelope);
      return;
    }
""",
     """    final wasIpSource =
        DirectPairingStore.extractDirectEndpoint(peerId).isNotEmpty;
    peerId = DirectPairingStore.canonicalConversationId(peerId);

    final messagekey = MessageKey(peerId, id);
    if (envelope != null && envelope.type != 'message') {
      await _handleEnvelope(messagekey, envelope);
      return;
    }
    // A peer the user blocked ("no longer receive") must not land here:
    // drop its messages before they are persisted or trigger any UI.
    if (gFFI.chatSettingsModel.isBlocked(peerId)) {
      RuntimeLogger.instance
          .info('CHAT-RX', 'drop blocked message peerId=$peerId');
      return;
    }
    _touchChatActivity(peerId);
"""),
])
