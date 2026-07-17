// LUODA 3.1.1 — In-session shared chat panel.
//
// Contract source: docs/3.1.1-features.md §12 item 4.
//
// Broadcast events arrive through ViewerSessionModel and sends use the
// generated Flutter/Rust bridge.

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/models/platform_model.dart';
import 'package:luoda_flutter/models/viewer_session_model.dart';

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
  final ViewerSessionModel viewerSessionModel;
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
    required this.viewerSessionModel,
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
  int _broadcastRevision = -1;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.viewerSessionModel.addListener(_handleViewerSessionUpdate);
    _handleViewerSessionUpdate();
  }

  @override
  void dispose() {
    widget.viewerSessionModel.removeListener(_handleViewerSessionUpdate);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _handleViewerSessionUpdate() {
    final model = widget.viewerSessionModel;
    if (_broadcastRevision == model.broadcastRevision) return;
    _broadcastRevision = model.broadcastRevision;
    final messages = <SharedChatMessage>[];
    for (final payload in model.broadcastChatPayloads) {
      try {
        messages.add(
          SharedChatMessage.parseEvent(payload, widget.selfViewerId),
        );
      } on FormatException {
        // Ignore malformed session control messages.
      }
    }
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(messages);
    });
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
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
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
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final senderId =
          widget.selfViewerId.isEmpty ? 'host' : widget.selfViewerId;
      final senderName = widget.selfDisplayName.isEmpty
          ? translate('Me')
          : widget.selfDisplayName;
      widget.viewerSessionModel.handleWireMessage(
        'BROADCAST_CHAT:$senderId:$senderName:$timestamp:$text',
      );
      _input.clear();
    } catch (_) {
      if (mounted) setState(() => _error = translate('Failed'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.forum_outlined,
                        size: 32,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.45),
                      ),
                      const SizedBox(height: 10),
                      Text(translate('Shared Chat')),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  onSubmitted: _sending ? null : (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: translate('Send'),
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _bubble(SharedChatMessage m) {
    final theme = Theme.of(context);
    final shortId = m.fromViewerId.length <= 8
        ? m.fromViewerId
        : m.fromViewerId.substring(0, 8);
    final align = m.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = m.isMe
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            m.fromName.isEmpty ? shortId : m.fromName,
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
