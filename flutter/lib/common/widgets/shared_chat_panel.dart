// LUODA 3.1.1 — In-session shared chat panel.
//
// Contract source: docs/3.1.1-features.md §12 item 4.
//
// Broadcast events arrive through ViewerSessionModel and sends use the
// generated Flutter/Rust bridge.

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/wechat_ui_tokens.dart';
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
    final dark = theme.brightness == Brightness.dark;
    final shortId = m.fromViewerId.length <= 8
        ? m.fromViewerId
        : m.fromViewerId.substring(0, 8);
    final displayName = m.fromName.isEmpty ? shortId : m.fromName;
    final bg = m.isMe
        ? dark
            ? const Color(0xFF3B7F55)
            : kWeChatOutgoingBubbleColor
        : dark
            ? const Color(0xFF2B2D32)
            : kWeChatIncomingBubbleColor;
    final initial =
        displayName.trim().isEmpty ? '?' : displayName.trim().characters.first;
    final avatar = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: str2color(displayName),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final bubble = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
          ),
          child: SelectableText(
            m.text,
            style: TextStyle(
              color: dark ? Colors.white : const Color(0xFF181818),
              fontSize: 14,
              height: 1.42,
            ),
          ),
        ),
        Positioned(
          top: 11,
          left: m.isMe ? null : -6,
          right: m.isMe ? -6 : null,
          child: CustomPaint(
            size: const Size(7, 10),
            painter: _SharedChatBubbleTailPainter(
              color: bg,
              pointsRight: m.isMe,
            ),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            m.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: m.isMe
            ? <Widget>[
                Flexible(child: bubble),
                const SizedBox(width: 10),
                avatar,
              ]
            : <Widget>[
                avatar,
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 4),
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: dark
                                ? const Color(0xFFA8AAAE)
                                : const Color(0xFF888888),
                          ),
                        ),
                      ),
                      bubble,
                    ],
                  ),
                ),
              ],
      ),
    );
  }
}

class _SharedChatBubbleTailPainter extends CustomPainter {
  const _SharedChatBubbleTailPainter({
    required this.color,
    required this.pointsRight,
  });

  final Color color;
  final bool pointsRight;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointsRight) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, size.height * 0.45)
        ..lineTo(0, size.height)
        ..close();
    } else {
      path
        ..moveTo(size.width, 0)
        ..lineTo(0, size.height * 0.45)
        ..lineTo(size.width, size.height)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SharedChatBubbleTailPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.pointsRight != pointsRight;
  }
}
