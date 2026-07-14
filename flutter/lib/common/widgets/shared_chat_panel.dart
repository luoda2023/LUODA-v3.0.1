// LUODA 3.1.1 — In-session shared chat panel contract widget.
//
// Contract source: docs/3.1.1-features.md §12 item 4.
//
// This file is a *contract stub*: it wires one frb entry point
// (`bind.sessionSendChatToViewer`) and renders messages delivered by
// the Rust side via the `BROADCAST_CHAT:<from>:<from_name>:<ts>:<text>`
// event prefix (`src/client/io_loop.rs` L2010). The same panel is
// reused by host (sends broadcast + viewer whispers) and viewers
// (sends only to host + other viewers). `flutter_rust_bridge_codegen`
// must be re-run on the online Flutter build host to regenerate
// `lib/generated_bridge.dart`; until then this file will not compile —
// that is by design and matches the "Dart codegen must run online"
// constraint recorded in docs/3.1.1-features.md L114.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/models/platform_model.dart';

/// One row in the shared chat log. We deliberately mirror the ChatMsg
/// shape (from RustDesk-flutter's `lib/models/chat_model.dart::ChatMsg`)
/// so that a follow-up pass can lift messages into the existing
/// `ChatModel` history without format conversion.
class SharedChatMessage {
  final String fromViewerId;
  final String fromName;
  final int timestamp;
  final String text;

  /// True iff the message originated on the local viewer (used to right-
  /// align bubbles in the UI even before the round-trip echo).
  final bool isMe;

  const SharedChatMessage({
    required this.fromViewerId,
    required this.fromName,
    required this.timestamp,
    required this.text,
    this.isMe = false,
  });

  /// Parse one `BROADCAST_CHAT:<from>:<from_name>:<ts>:<text>` event
  /// payload (after the `BROADCAST_CHAT:` prefix has been stripped by
  /// the event channel router). `text` is the **remainder** of the
  /// payload after the third `:` — Rust uses `splitn(4, ':')`-style
  /// splitting (see `io_loop.rs` L2018-L2023), so colons inside the
  /// text body are preserved.
  factory SharedChatMessage.parseEvent(String payload, String selfViewerId) {
    final parts = payload.split(':');
    if (parts.length < 4) {
      throw FormatException('malformed BROADCAST_CHAT payload: $payload');
    }
    final from = parts[0];
    final fromName = parts[1];
    final ts = int.tryParse(parts[2]) ?? 0;
    // Body may contain colons — rejoin.
    final text = parts.sublist(3).join(':');
    return SharedChatMessage(
      fromViewerId: from,
      fromName: fromName,
      timestamp: ts,
      text: text,
      isMe: from == selfViewerId,
    );
  }
}

/// Shared chat panel.
///
/// The widget subscribes to the host-side `broadcast_chat` event
/// stream and the client-side whisper echo. The host sees a wider
/// input-bar with a viewer-id hint (with empty meaning broadcast).
/// Viewers see only a single input line whose sends always target the
/// session host via `bind.sessionSendChatToViewer(... toViewerId: '' ...)`.
class SharedChatPanel extends StatefulWidget {
  final UuidValue sessionId;
  final bool isHost;
  final String selfViewerId;
  final String selfDisplayName;

  /// Optional injector for the FFI call — used by tests; production
  /// code leaves null.
  final Future<void> Function({
    required UuidValue sessionId,
    required String toViewerId,
    required String text,
  })? sendChatToViewer;

  const SharedChatPanel({
    super.key,
    required this.sessionId,
    this.isHost = false,
    this.selfViewerId = '',
    this.selfDisplayName = '',
    this.sendChatToViewer,
  });

  @override
  State<SharedChatPanel> createState() => _SharedChatPanelState();
}

class _SharedChatPanelState extends State<SharedChatPanel> {
  final List<SharedChatMessage> _messages = <SharedChatMessage>[];
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  StreamSubscription<SharedChatMessage?>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _watchBroadcastChatStream();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  /// Hook point for the event-stream listener that surfaces
  /// `BROADCAST_CHAT:...` events back into the panel.
  ///
  /// Contract: the Rust side emits `BROADCAST_CHAT:<from>:<from_name>:<ts>:<text>`
  /// (see `src/client/io_loop.rs` L2010). On the online Flutter build
  /// host, after `flutter_rust_bridge_codegen` re-runs, wire this
  /// subscription to the native-event channel used by other 3.1.1
  /// viewer widgets and surface the parsed payload via
  /// `_onBroadcastChat(...)`.
  ///
  /// TODO(codegen-online): replace the dummy subscription below with
  /// a real listener once `lib/generated_bridge.dart` is regenerated.
  StreamSubscription<SharedChatMessage?>? _watchBroadcastChatStream() {
    // Intentionally a no-op stub.
    return null;
  }

  void _onBroadcastChat(SharedChatMessage msg) {
    setState(() => _messages.add(msg));
    // Scroll-to-bottom on next frame so the latest message is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    try {
      if (widget.sendChatToViewer != null) {
        await widget.sendChatToViewer!(
          sessionId: widget.sessionId,
          toViewerId: '',
          text: text,
        );
      } else {
        await bind.sessionSendChatToViewer(
          sessionId: widget.sessionId,
          toViewerId: '',
          text: text,
        );
      }
      // Optimistic local echo so the bubble shows up before the
      // round-trip `BROADCAST_CHAT:self:...` event arrives.
      _onBroadcastChat(SharedChatMessage(
        fromViewerId: widget.selfViewerId,
        fromName: widget.selfDisplayName,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        text: text,
        isMe: true,
      ));
      _input.clear();
    } catch (_) {
      // Best-effort; surface non-fatal errors in a future pass.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: _messages.length,
            itemBuilder: (_, i) => _bubble(_messages[i]),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: translate('Shared Chat'),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _send,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bubble(SharedChatMessage m) {
    final theme = Theme.of(context);
    final align = m.isMe
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final bg = m.isMe
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            m.fromName.isEmpty ? m.fromViewerId.substring(0, 8) : m.fromName,
            style: theme.textTheme.labelSmall,
          ),
          Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(m.text),
          ),
        ],
      ),
    );
  }
}
