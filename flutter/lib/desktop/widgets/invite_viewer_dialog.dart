// LUODA 3.1.1 — Host-side "Invite Viewer" dialog.
//
// Contract source: docs/3.1.1-features.md §12 item 1.
//
// InviteToken events arrive through ViewerSessionModel after the request is
// sent through the generated Flutter/Rust bridge.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/direct_viewer_invite.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/models/platform_model.dart';
import 'package:luoda_flutter/models/viewer_session_model.dart';

/// Result returned by [InviteViewerDialog] when the host taps "Generate"
/// or closes the dialog after a token has been minted.
///
/// `shortCode` is the 12-char Crockford base32 short code produced by the
/// server (Rust: `src/server/invite_code.rs::encode_short_code`). It is
/// the same string embedded in the `luoda://join/<short_code>` deep link
/// encoded into the QR image.
class InviteViewerResult {
  final String shortCode;
  final String? sessionId;
  final int? ttlMinutes;
  final bool oneShot;

  const InviteViewerResult({
    required this.shortCode,
    this.sessionId,
    this.ttlMinutes,
    this.oneShot = false,
  });
}

/// Host-side "Invite Viewer" dialog.
///
/// Flow (per docs/3.1.1-features.md §12 item 1):
///   1. Host opens this dialog with the active `sessionId`.
///   2. Host picks TTL (minutes) and one-shot flag, taps "Generate".
///   3. We call `bind.sessionRequestInviteToken(...)`; the Rust side
///      round-trips an `InviteToken` misc message back to the flutter
///      event channel with prefix `INVITE_TOKEN:<short>:<sid>:<exp>:<one_shot>`
///      (see `src/client/io_loop.rs` L1962).
///   4. We render the 12-char short code + a QR for `luoda://join/<short>`.
///   5. Host may "Copy" the link or close the dialog; closing returns
///      an [InviteViewerResult] with the short code so the caller can
///      surface it / share via chat.
class InviteViewerDialog extends StatefulWidget {
  final UuidValue sessionId;
  final String hostLabel;
  final String hostEndpoint;
  final ViewerSessionModel viewerSessionModel;

  /// Optional injector for the FFI call — only used by tests; production
  /// code leaves this null and the dialog binds against [platformFFI.ffiBind].
  final Future<void> Function({
    required UuidValue sessionId,
    required int ttlMinutes,
    required bool oneShot,
  })? requestInviteToken;

  /// Optional callback: when non-null, a "Send to Chat" button is shown
  /// alongside "Copy Invite Link". The dialog passes the deeplink string
  /// so the caller can dispatch it via [ChatModel.sendText].
  final void Function(String inviteLink)? onSendToChat;

  const InviteViewerDialog({
    super.key,
    required this.sessionId,
    required this.hostLabel,
    required this.hostEndpoint,
    required this.viewerSessionModel,
    this.requestInviteToken,
    this.onSendToChat,
  });

  /// Convenience wrapper — pushes the dialog onto [context] and returns
  /// the [InviteViewerResult] produced when the host closes the dialog.
  static Future<InviteViewerResult?> show(
    BuildContext context, {
    required UuidValue sessionId,
    required String hostLabel,
    required String hostEndpoint,
    required ViewerSessionModel viewerSessionModel,
    void Function(String inviteLink)? onSendToChat,
  }) {
    return showDialog<InviteViewerResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => InviteViewerDialog(
        sessionId: sessionId,
        hostLabel: hostLabel,
        hostEndpoint: hostEndpoint,
        viewerSessionModel: viewerSessionModel,
        onSendToChat: onSendToChat,
      ),
    );
  }

  @override
  State<InviteViewerDialog> createState() => _InviteViewerDialogState();
}

class _InviteViewerDialogState extends State<InviteViewerDialog> {
  static const List<int> _ttlOptions = [15, 30, 60, 120, 240, 480];
  int _ttlMinutes = 60;
  bool _oneShot = false;
  bool _generating = false;

  String? _shortCode;
  String? _sessionIdEcho;
  int? _expiresAt;
  bool? _oneShotEcho;
  String? _lastError;

  int _inviteRevision = 0;

  @override
  void initState() {
    super.initState();
    _inviteRevision = widget.viewerSessionModel.inviteRevision;
    widget.viewerSessionModel.addListener(_handleViewerSessionUpdate);
  }

  @override
  void dispose() {
    widget.viewerSessionModel.removeListener(_handleViewerSessionUpdate);
    super.dispose();
  }

  /// Reads a new token delivered through the active session event model.
  void _handleViewerSessionUpdate() {
    final model = widget.viewerSessionModel;
    if (_inviteRevision == model.inviteRevision) return;
    _inviteRevision = model.inviteRevision;
    final payload = model.inviteTokenPayload;
    if (payload == null) return;
    final parts = payload.split(':');
    if (parts.length != 4) {
      if (mounted) {
        setState(() {
          _generating = false;
          _lastError = translate('Invalid format');
        });
      }
      return;
    }
    _onInviteToken(
      parts[0],
      parts[1],
      int.tryParse(parts[2]) ?? 0,
      parts[3] == 'true' || parts[3] == '1',
    );
  }

  void _onInviteToken(String short, String sid, int exp, bool oneShot) {
    if (!mounted) return;
    setState(() {
      _shortCode = short;
      _sessionIdEcho = sid;
      _expiresAt = exp;
      _oneShotEcho = oneShot;
      _generating = false;
      _lastError = null;
    });
  }

  Future<void> _generate() async {
    if (!isViewerConnectionTarget(widget.hostEndpoint)) {
      setState(() {
        _lastError = translate('ID or IP:port');
      });
      return;
    }
    setState(() {
      _generating = true;
      _lastError = null;
    });
    try {
      if (widget.requestInviteToken != null) {
        await widget.requestInviteToken!(
          sessionId: widget.sessionId,
          ttlMinutes: _ttlMinutes,
          oneShot: _oneShot,
        );
      } else {
        // Online-codegen: `bind.sessionRequestInviteToken(...)` resolves
        // to the wire method generated from `flutter_ffi::session_request_invite_token`
        // (`src/flutter_ffi.rs` L750).
        await bind.sessionRequestInviteToken(
          sessionId: widget.sessionId,
          ttlMinutes: _ttlMinutes,
          oneShot: _oneShot,
        );
      }
      // The token arrives asynchronously through ViewerSessionModel.
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _lastError = e.message ?? e.code;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _lastError = e.toString();
      });
    }
  }

  String get _deeplink => ViewerInviteLink(
        endpoint: widget.hostEndpoint,
        token: _shortCode ?? '',
      ).toUri().toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = 380.0;

    return AlertDialog(
      title: Text(translate('Invite Viewer')),
      content: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.hostLabel,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_shortCode == null)
              _buildGenerator(theme)
            else
              _buildToken(theme),
            if (_lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                _lastError!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop<InviteViewerResult>(_result()),
          child: Text(translate('Cancel')),
        ),
        if (_shortCode != null) ...[
          TextButton(
            onPressed: _copyLink,
            child: Text(translate('Copy Invite Link')),
          ),
          if (widget.onSendToChat != null)
            TextButton(
              onPressed: _sendToChat,
              child: Text(translate('Send to Chat')),
            ),
        ],
      ],
    );
  }

  Widget _buildGenerator(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(translate('viewer_ttl')),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: _ttlMinutes,
              items: _ttlOptions
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text('$m min'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _ttlMinutes = v ?? _ttlMinutes),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(translate('max_viewers')),
          value: !_oneShot,
          onChanged: (v) => setState(() => _oneShot = !v),
        ),
        if (_oneShot)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              'one-shot',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _generating ? null : _generate,
          child: Text(_generating
              ? 'Generating...'
              : translate('Generate Invite Token')),
        ),
      ],
    );
  }

  Widget _buildToken(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          _shortCode ?? '',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontFamily: 'monospace',
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: QrImageView(
            data: _deeplink,
            version: QrVersions.auto,
            size: 220,
            gapless: true,
            embeddedImage: null,
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(
          _deeplink,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  InviteViewerResult? _result() {
    if (_shortCode == null) return null;
    return InviteViewerResult(
      shortCode: _shortCode!,
      sessionId: _sessionIdEcho,
      ttlMinutes: _ttlMinutes,
      oneShot: _oneShotEcho ?? _oneShot,
    );
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _deeplink));
    if (mounted) {
      showToast(translate('Copy Invite Link'));
    }
  }

  void _sendToChat() {
    final link = _deeplink;
    widget.onSendToChat?.call(link);
    if (mounted) {
      showToast(translate('Sent to Chat'));
      Navigator.of(context).pop<InviteViewerResult>(_result());
    }
  }
}
