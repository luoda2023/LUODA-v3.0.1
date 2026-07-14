# CHANGELOG

All notable changes to LUODA Remote Desktop are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 3.1.1 - viewer + chat broadcast

### Added

- **Viewer role** added to the session model (server::viewer_state::ViewerState
  on server::Connection). A connection with viewer_state = Some(...) is
  view-only: every non-viewer inbound message (keyboard, mouse, clipboard,
  file, terminal, switch display, elevation) is dropped at the dispatcher in
  src/server/connection.rs (see the viewer routing block).
- **Invite token registry** src/server/viewer_registry.rs with TTL
  (default 30 min, configurable 5/15/30/60 min or one-shot), max-viewer cap
  (default 8), per-host token / viewer tables, GC loop, promote, kick,
  purge, set_max_viewers, list_viewers, snapshot.
- **Multi-party chat broadcast** src/server/chat_broadcast.rs: per-host
  ChatHub with public / private / route / join / leave /
  peer_count. Routed delivery model keeps the hub itself network-agnostic.
- **Direct channel for viewer streams** src/server/viewer_direct_channel.rs.
- **Protocol extensions** in libs/hbb_common/protos/message.proto:
  JoinAsViewer, InviteToken, ViewerListUpdate, ViewerInfo,
  KickViewer, PromoteViewer, ChatBroadcast, ChatChannel,
  RaiseHand. New union variants are appended so v3.0.1 peers ignore them.
- **Integration tests** tests/viewer_p2p.rs covering token issue / admit /
  cap hit / promote / kick / chat broadcast routing / session purge.
- **Documentation**: docs/3.1.1-features.md PRD + this CHANGELOG entry +
  README 3.1.1 section.

### Changed

- Cargo.toml package version bumped 3.0.1 -> 3.1.1.
- src/server/connection.rs message dispatcher now branches on
  viewer_state.is_some() before falling through to the legacy handler.

### Not in 3.1.1 (deferred)

- Flutter-side 3.1.1 UI (invite dialog, join-by-code, participant list,
  shared chat panel widget) is not in this server-only drop; the protocol
  surface and server integration are landed first so the client can be
  consumed in a follow-up release. This must be built in an online Flutter
  build environment (it pulls `flutter pub get` + `flutter_rust_bridge_codegen`
  and the local policy forbids running those builders locally).
- i18n strings for the new viewer/chat keys (17 keys) were added to src/lang/{en,cn,tw}.rs;
  they belong with the Flutter follow-up release.

### Wired since the deferred listing was first written

- `viewer_registry::start_gc_loop()` is now spawned on the server startup
  path (`src/server.rs:621`), giving 60s periodic purge of expired invite
  tokens and stale viewer entries.
- `RequestInviteToken` (proto id 43, message `RequestInviteToken`) is now
  handled in `src/server/connection.rs::handle_request_invite_token` (L5666):
  a controlling peer can mint a short-code invite token (TTL / one-shot are
  honoured) and the response `InviteToken` is delivered back on the same
  connection.
- Short-code (Crockford base32, 12 chars) encode/decode land in the new
  `src/server/invite_code.rs`; `Registry::issue_token` writes the
  `short_codes` reverse index and `Registry::resolve_short_code` accepts the
  normalised 12-char code (hyphens / spaces / case / confusables normalised);
  `connection.rs::handle_join_as_viewer` resolves the short code first and
  falls back to the legacy full-token path.
- Server-side fan-out is linked: `src/server/viewer_fanout.rs` exposes
  `emit_chat` / `emit_viewer_list_snapshot` / `emit_to_viewer` /
  `emit_viewer_list_update`; `connection.rs` calls these from the admit /
  kick / promote / chat routes so `ViewerListUpdate`, `ChatBroadcast`, and
  `KickViewer` ack now reach every viewer and the host over the wire.

### i18n keys landed (2026-04-28)

- 14 viewer-control / chat-broadcast i18n keys (`Invite Viewer`,
  `Generate Invite Token`, `Invite Code`, `Invite Link`,
  `Copy Invite Link`, `Join as Viewer`, `Max Viewers`, `Token TTL`,
  `Kick Viewer`, `Promote Viewer`, `Raise Hand`, `Lower Hand`,
  `Viewer List`, `Shared Chat`) are appended to `src/lang/en.rs`,
  `src/lang/cn.rs`, `src/lang/tw.rs`. The Rust HashMap-driven `translate()`
  surface that `flutter_ffi::translate` already exposes is therefore
  ready for the Flutter follow-up to consume directly; no
  `flutter/langs/*.json` resource is required by the project's i18n
  architecture.
- The Flutter-side widget contracts (`InviteDialog`, `JoinAsViewerDialog`,
  `ViewerListPanel`, `SharedChatPanel`) are now specified in
  `docs/3.1.1-features.md` 搂12 so an online Flutter build environment can
  land the four Dart widgets without further Rust-side plumbing. The Rust
  frb entry points (`session_request_invite_token`,
  `session_join_as_viewer`, `session_send_chat_to_viewer`,
  `session_kick_viewer`, `session_promote_viewer`, `session_raise_hand`)
  are already exposed in `src/flutter_ffi.rs`.
### Flutter widget contracts landed (2026-04-28)

The four Dart widget *contract stubs* landed at:
- `flutter/lib/desktop/widgets/invite_viewer_dialog.dart` (host: issue token)
- `flutter/lib/common/widgets/join_viewer_page.dart`   (client: join by code)
- `flutter/lib/common/widgets/viewer_list_panel.dart`  (in-session list)
- `flutter/lib/common/widgets/shared_chat_panel.dart`  (shared chat)

Each stub wires its frb call points (`bind.sessionRequestInviteToken`,
`bind.sessionJoinAsViewer`, `bind.sessionKickViewer`,
`bind.sessionPromoteViewer`, `bind.sessionSendChatToViewer`,
`bind.sessionRaiseHand`) and event prefixes (`INVITE_TOKEN:`, `VIEWER_LIST:`,
`BROADCAST_CHAT:`) exactly as specified in `docs/3.1.1-features.md` §12.
Rust-side `flutter_ffi` entry points are unchanged.

Sole remaining blocker for compiles: an online build environment must run
`flutter pub get` + `flutter_rust_bridge_codegen` to regenerate
`lib/generated_bridge.dart` so the `bind.*Session*` symbols called from the
stubs resolve. Local policy forbids running those builders locally.

### i18n keys for viewer / chat UI (2026-04-28)

The 17 viewer-control i18n keys listed in `docs/3.1.1-features.md` §11 are now landed in `src/lang/en.rs`, `src/lang/cn.rs`, `src/lang/tw.rs`:

- invite_viewer / generate_invite_token / invite_code / invite_link
- copy_invite_link / join_as_viewer / max_viewers / viewer_ttl
- kick_viewer / promote_viewer / raise_hand / lower_hand
- viewer_list / shared_chat / display_name / one_shot
- broadcast_chat_hint

Each key stores the phrase itself as the HashMap key (consistent with the existing RustDesk i18n pattern so `translate("Invite Viewer")` resolves through the same `lang.rs::T` table). Other locale mods are filled in by the online Flutter build environment when it rebuilds language packs.

The 17 snake_case identifiers above are logical labels in this changelog; the actual `lang.rs::T` HashMap keys are the Title Case English phrases (`"Invite Viewer"`, `"Generate Invite Token"`, `"Invite Code"`, `"Invite Link"`, `"Copy Invite Link"`, `"Join as Viewer"`, `"Max Viewers"`, `"Token TTL"`, `"Kick Viewer"`, `"Promote Viewer"`, `"Raise Hand"`, `"Lower Hand"`, `"Viewer List"`, `"Shared Chat"`, `"Display Name"`, `"One Shot"`, `"Broadcast Chat Hint"`). This matches the existing i18n style (e.g., `"Audio Input"`, `"Connection Error"`) and keeps `translate("Invite Viewer")` a self-resolving lookup.

### End-to-end integration coverage (2026-04-28)

`tests/viewer_session.rs` added. It is a higher-level integration contract that walks the full server-side flow:

- issue token -> short-code -> resolve -> `JoinAsViewer` admit
- viewer routed view-only through `Connection` dispatch
- public / private `ChatBroadcast` routing through `ChatHub`
- host `KickViewer` / `PromoteViewer` lifecycle
- registry GC evicts expired token + viewer entries

The existing `tests/viewer_p2p.rs` keeps covering the low-level registry / chat hub / direct channel primitives. Together they form the contract that must keep passing while the Flutter UI layer is wired up online.
See docs/3.1.1-features.md "尚未落地" section for the up-to-date status.

---

## 3.0.1 - baseline

Initial public baseline of LUODA Remote Desktop (Rust core + Flutter shell),
single-host remote desktop session with encrypted P2P/relay transport,
file transfer, clipboard sharing, multi-monitor support.