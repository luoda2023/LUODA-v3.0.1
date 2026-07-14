// LUODA 3.1.1 — Client-side "Join as Viewer" page contract widget.
//
// Contract source: docs/3.1.1-features.md §12 item 2.
//
// This file is a *contract stub*. The call site
// `bind.sessionJoinAsViewer(...)` resolves to the frb wrapper generated
// from `flutter_ffi::session_join_as_viewer` (`src/flutter_ffi.rs` L761).
// `flutter_rust_bridge_codegen` must be re-run on the online Flutter
// build host to materialise `lib/generated_bridge.dart`; until then
// this file will not compile — that is by design and matches the
// "Dart codegen must run online" constraint recorded in
// docs/3.1.1-features.md L114.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/models/platform_model.dart';

/// Page where a viewer pastes a 12-char Crockford short code (or full
/// invite token) and joins the target session as an audience/viewer.
///
/// Flow (per docs/3.1.1-features.md §12 item 2):
///   1. Viewer receives an `luoda://join/<short_code>` deep link, or
///      opens this page manually and types the short code.
///   2. Viewer optionally overrides the auto-detected display name.
///   3. On submit we generate a fresh UUIDv4 as `viewerId` and call
///      `bind.sessionJoinAsViewer(...)`. The Rust side
///      (`src/server/connection.rs::handle_join_as_viewer` L5501)
///      resolves the short code via `Registry::resolve_short_code`
///      (`src/server/invite_code.rs`), and the viewer is admitted into
///      the session's viewer registry.
class JoinViewerPage extends StatefulWidget {
  final UuidValue? sessionIdHint;
  final String? initialToken;
  final String? initialDisplayName;

  /// Optional injector for the FFI call — used by tests; production
  /// code leaves this null and the page binds against [platformFFI.ffiBind].
  final Future<void> Function({
    required UuidValue sessionId,
    required String token,
    required String viewerId,
    required String displayName,
  })? joinAsViewer;

  const JoinViewerPage({
    super.key,
    this.sessionIdHint,
    this.initialToken,
    this.initialDisplayName,
    this.joinAsViewer,
  });

  @override
  State<JoinViewerPage> createState() => _JoinViewerPageState();
}

class _JoinViewerPageState extends State<JoinViewerPage> {
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _displayNameCtrl;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tokenCtrl = TextEditingController(text: widget.initialToken ?? '');
    _displayNameCtrl =
        TextEditingController(text: widget.initialDisplayName ?? _defaultName());
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  static String _defaultName() {
    // Online-codegen: wire to `bind.getMyName()` once that helper is
    // re-exported (already available in RustDesk-flutter as
    // `bind.mainGetMyName()`). For now we leave a placeholder.
    return '';
  }

  String _normalizeToken(String raw) {
    // Mirror `normalize_short_code` in `src/server/invite_code.rs`:
    // strip whitespace and hyphens, uppercase. The Rust side re-runs the
    // same normalisation; doing it client-side gives a snappier UX.
    return raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  }

  Future<void> _submit() async {
    final raw = _tokenCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Invite code cannot be empty');
      return;
    }
    final token = _normalizeToken(raw);
    final displayName = _displayNameCtrl.text.trim().isNotEmpty
        ? _displayNameCtrl.text.trim()
        : 'viewer';
    final viewerId = const Uuid().v4();
    final sessionId = widget.sessionIdHint;
    if (sessionId == null) {
      // Without an active session hint we cannot dial into the viewer
      // channel — the deep-link / navigation path that reached this
      // page is expected to supply one. Surface a clear error rather
      // than silently*failing.
      setState(() => _error = 'missing session');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      if (widget.joinAsViewer != null) {
        await widget.joinAsViewer!(
          sessionId: sessionId,
          token: token,
          viewerId: viewerId,
          displayName: displayName,
        );
      } else {
        // Online-codegen target — wire to frb-generated helper.
        await bind.sessionJoinAsViewer(
          sessionId: sessionId,
          token: token,
          viewerId: viewerId,
          displayName: displayName,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on PlatformException catch (e) {
      setState(() {
        _submitting = false;
        _error = e.message ?? e.code;
      });
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(translate('Join as Viewer')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _tokenCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: translate('Invite Code'),
                    hintText: 'ABCD-EFGH-JKMN',
                    border: const OutlineInputBorder(),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _displayNameCtrl,
                  decoration: InputDecoration(
                    labelText: translate('Display Name'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(translate('Join as Viewer')),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
