// LUODA 3.1.1 — In-session viewer list panel contract widget.
//
// Contract source: docs/3.1.1-features.md §12 item 3.
//
// This file is a *contract stub*: it wires four frb entry points
// (`bind.sessionKickViewer`, `bind.sessionPromoteViewer`,
// `bind.sessionRaiseHand`) and renders
// `ViewerInfo` records delivered by the Rust side via the
// `VIEWER_LIST:<max>:<total_uplink_bps>:<count>:<body>` event prefix
// (see `src/client/io_loop.rs` L1995). `flutter_rust_bridge_codegen`
// must be re-run on the online Flutter build host to regenerate
// `lib/generated_bridge.dart`; until then this file will not compile —
// that is by design and matches the "Dart codegen must run online"
// constraint recorded in docs/3.1.1-features.md L114.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/models/platform_model.dart';

/// One row in the session's viewer registry as surfaced by the Rust
/// side via `Misc::ViewerListUpdate` (`src/client/io_loop.rs` L1979).
class ViewerInfo {
  final String viewerId;
  final String displayName;
  final int joinedAt;
  final bool promoted;

  const ViewerInfo({
    required this.viewerId,
    required this.displayName,
    required this.joinedAt,
    required this.promoted,
  });

  /// Parse one CSV segment as emitted by `io_loop.rs::ViewerListUpdate`:
  /// `<viewer_id>|<display_name>|<promoted>|<joined_at>`.
  ///
  /// The Rust side always emits this shape (see L1989-L1993), so parsing
  /// can assume a strict 4-field layout.
  factory ViewerInfo.fromCsvSegment(String segment) {
    final parts = segment.split('|');
    if (parts.length != 4) {
      throw FormatException(
          'malformed ViewerInfo segment (got ${parts.length} fields): $segment');
    }
    return ViewerInfo(
      viewerId: parts[0],
      displayName: parts[1],
      promoted: parts[2] == 'true' || parts[2] == '1',
      joinedAt: int.tryParse(parts[3]) ?? 0,
    );
  }

  /// Optional parse helper for tests; production code parses the full
  /// payload via [parseViewerListPayload] below.
  static List<ViewerInfo> parseBody(String body) {
    if (body.isEmpty) return const [];
    return body
        .split(';')
        .where((s) => s.isNotEmpty)
        .map(ViewerInfo.fromCsvSegment)
        .toList(growable: false);
  }
}

/// Aggregate payload corresponding to one `VIEWER_LIST:...` event.
class ViewerListSnapshot {
  final int maxViewers;
  final int totalUplinkBps;
  final List<ViewerInfo> viewers;

  const ViewerListSnapshot({
    required this.maxViewers,
    required this.totalUplinkBps,
    required this.viewers,
  });

  /// Parse the payload portion after the `VIEWER_LIST:` prefix.
  /// Format per `io_loop.rs` L1996: `<max>:<total_uplink_bps>:<count>:<body>`.
  factory ViewerListSnapshot.parseEvent(String payload) {
    final top = payload.split(':');
    if (top.length < 4) {
      throw FormatException('malformed VIEWER_LIST payload: $payload');
    }
    final maxViewers = int.tryParse(top[0]) ?? 0;
    final totalUplinkBps = int.tryParse(top[1]) ?? 0;
    final count = int.tryParse(top[2]) ?? 0;
    // `body` may itself contain colons? No — Rust uses `;` as the
    // viewer separator and `|` as field separator; `:` only appears
    // between the 4 leading integers + body. So a single split(':' 3)
    // is sufficient.
    final body = top.sublist(3).join(':');
    final viewers = ViewerInfo.parseBody(body);
    if (count != viewers.length) {
      // Not fatal — the Rust count is redundant with |body|. Just log.
    }
    return ViewerListSnapshot(
      maxViewers: maxViewers,
      totalUplinkBps: totalUplinkBps,
      viewers: viewers,
    );
  }
}

/// In-session viewer list panel.
///
/// The widget subscribes to the host-side `viewer_list_update_stream`
/// (per docs §12 item 3) exposed as `VIEWER_LIST:...` events through
/// the same native-event channel the rest of the 3.1.1 viewer widgets
/// use. Each snapshot is rendered as a vertical list of [ViewerInfo];
/// when `isHost` is true, every row gets **Kick** and **Promote**
/// buttons that call `bind.sessionKickViewer` / `bind.sessionPromoteViewer`.
class ViewerListPanel extends StatefulWidget {
  final UuidValue sessionId;
  final bool isHost;
  final String hostViewerId;

  /// Optional injector for the kick/promote FFI calls — used by tests;
  /// production code leaves them null and we bind against
  /// [platformFFI.ffiBind].
  final Future<void> Function({
    required UuidValue sessionId,
    required String viewerId,
    required String reason,
  })? kickViewer;
  final Future<void> Function({
    required UuidValue sessionId,
    required String viewerId,
  })? promoteViewer;

  /// The viewer id of the local participant. When non-empty and
  /// [isHost] is false, the panel renders a Raise / Lower Hand
  /// toggle in the header that drives
  /// `bind.sessionRaiseHand(selfViewerId, raised)`.
  final String selfViewerId;

  /// Optional injector for the raise-hand FFI call ? used by
  /// tests; production code leaves null.
  final Future<void> Function({
    required UuidValue sessionId,
    required String viewerId,
    required bool raised,
  })? raiseHand;

  const ViewerListPanel({
    super.key,
    required this.sessionId,
    this.isHost = false,
    this.hostViewerId = '',
    this.selfViewerId = '',
    this.kickViewer,
    this.promoteViewer,
    this.raiseHand,
  });

  @override
  State<ViewerListPanel> createState() => _ViewerListPanelState();
}

class _ViewerListPanelState extends State<ViewerListPanel> {
  ViewerListSnapshot? _snapshot;
  StreamSubscription? _sub;
  bool _raised = false;

  @override
  void initState() {
    super.initState();
    _sub = _watchViewerListStream();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Hook point for the event-stream listener that surfaces
  /// `Misc::ViewerListUpdate` events back into the panel.
  ///
  /// Contract: the Rust side emits `VIEWER_LIST:<max>:<total_uplink_bps>:<count>:<body>`
  /// (see `src/client/io_loop.rs` L1995); each `;`-separated `body`
  /// segment has shape `<viewer_id>|<display_name>|<promoted>|<joined_at>`.
  ///
  /// TODO(codegen-online): replace the dummy subscription below with
  /// a real listener once `lib/generated_bridge.dart` is regenerated
  /// and surface the parsed payload via `_onViewerList(...)`.
  StreamSubscription<ViewerListSnapshot?>? _watchViewerListStream() {
    // Intentionally a no-op stub.
    return null;
  }

  void _onViewerList(ViewerListSnapshot snapshot) {
    setState(() => _snapshot = snapshot);
  }

  Future<void> _kick(ViewerInfo v) async {
    try {
      if (widget.kickViewer != null) {
        await widget.kickViewer!(
          sessionId: widget.sessionId,
          viewerId: v.viewerId,
          reason: 'host_kick',
        );
      } else {
        await bind.sessionKickViewer(
          sessionId: widget.sessionId,
          viewerId: v.viewerId,
          reason: 'host_kick',
        );
      }
    } catch (_) {
      // Best-effort; surface non-fatal errors in a future pass.
    }
  }

  Future<void> _promote(ViewerInfo v) async {
    try {
      if (widget.promoteViewer != null) {
        await widget.promoteViewer!(
          sessionId: widget.sessionId,
          viewerId: v.viewerId,
        );
      } else {
        await bind.sessionPromoteViewer(
          sessionId: widget.sessionId,
          viewerId: v.viewerId,
        );
      }
    } catch (_) {
      // Best-effort; surface non-fatal errors in a future pass.
    }
  }

  Future<void> _raiseHand() async {
    final next = !_raised;
    try {
      if (widget.raiseHand != null) {
        await widget.raiseHand!(
          sessionId: widget.sessionId,
          viewerId: widget.selfViewerId,
          raised: next,
        );
      } else {
        await bind.sessionRaiseHand(
          sessionId: widget.sessionId,
          viewerId: widget.selfViewerId,
          raised: next,
        );
      }
      if (mounted) setState(() => _raised = next);
    } catch (_) {
      // Best-effort; surface non-fatal errors in a future pass.
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    if (snap == null) {
      return Center(child: Text(translate('Viewer List')));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Text(translate('Viewer List')),
              const SizedBox(width: 8),
              Text('${snap.viewers.length} / ${snap.maxViewers}',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              if (!widget.isHost && widget.selfViewerId.isNotEmpty)
                TextButton.icon(
                  onPressed: _raiseHand,
                  icon: Icon(
                    _raised ? Icons.pan_tool : Icons.back_hand_outlined,
                    color: _raised
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  label: Text(_raised
                      ? translate('Lower Hand')
                      : translate('Raise Hand')),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: snap.viewers.length,
            itemBuilder: (_, i) => _row(snap.viewers[i]),
          ),
        ),
      ],
    );
  }

  Widget _row(ViewerInfo v) {
    final isSelf = widget.hostViewerId.isNotEmpty && widget.hostViewerId == v.viewerId;
    return ListTile(
      dense: true,
      leading: Icon(v.promoted ? Icons.handshake_outlined : Icons.visibility_outlined),
      title: Text(v.displayName.isEmpty ? v.viewerId.substring(0, 8) : v.displayName),
      subtitle: Text(
        // joinedAt is epoch seconds on the Rust side (io_loop.rs L1991);
        // we render a short relative stamp here, expanded in a follow-up.
        '${v.joinedAt}',
      ),
      trailing: widget.isHost && !isSelf
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => _kick(v),
                  child: Text(translate('Kick Viewer')),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: v.promoted ? null : () => _promote(v),
                  child: Text(translate('Promote Viewer')),
                ),
              ],
            )
          : null,
    );
  }
}
