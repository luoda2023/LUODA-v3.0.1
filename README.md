# LUODA Remote Desktop

A self-hosted remote desktop application built with Rust, providing secure and efficient remote access solution.

## Features

- Self-hosted server for complete data control
- Cross-platform support (Windows, macOS, Linux, Android, iOS)
- High performance with low latency
- End-to-end encryption
- File transfer and clipboard sharing
- Multi-monitor support

## LUODA 3.1.1 extras

- **Invite-only view-only audience** (`JoinAsViewer` / `InviteToken`): the
  controlling peer can share a short invite code with third parties who join
  the session as view-only viewers; no keyboard / mouse / clipboard / file
  channel is exposed to them.
- **Per-host viewer registry** with token TTL, max-viewer cap (default 8),
  `KickViewer`, `PromoteViewer` (badge-only - data path stays view-only).
- **Multi-party chat broadcast** (public + 1:1 private `ChatChannel`) with
  in-memory per-session hub; chat logs are not persisted server-side.
- **Raise hand** signal for viewers; host UI reflects the badge.
- **17 i18n keys for viewer / chat UI** (invite_viewer / generate_invite_token /
  invite_code / invite_link / copy_invite_link / join_as_viewer /
  max_viewers / viewer_ttl / kick_viewer / promote_viewer /
  
raise_hand / lower_hand / viewer_list / shared_chat /
  display_name / one_shot / broadcast_chat_hint) have landed in
  src/lang/en.rs, src/lang/cn.rs, src/lang/tw.rs; other locale mods are
  filled in by the online Flutter build when it rebuilds language packs.

The 17 snake_case names above are logical labels in this README; the actual `lang.rs::T` HashMap keys are the Title Case English phrases (`"Invite Viewer"`, `"Generate Invite Token"`, `"Invite Code"`, `"Invite Link"`, `"Copy Invite Link"`, `"Join as Viewer"`, `"Max Viewers"`, `"Token TTL"`, `"Kick Viewer"`, `"Promote Viewer"`, `"Raise Hand"`, `"Lower Hand"`, `"Viewer List"`, `"Shared Chat"`, `"Display Name"`, `"One Shot"`, `"Broadcast Chat Hint"`). This matches the existing i18n style (e.g., `"Audio Input"`, `"Connection Error"`) and keeps `translate("Invite Viewer")` a self-resolving lookup.

- **Two-tier test coverage**: `tests/viewer_p2p.rs` covers the low-level
  primitives (registry / chat hub / direct channel), and
  `tests/viewer_session.rs` walks the full server-side contract end-to-end
  (issue token -> short-code resolve -> consume -> admit -> chat -> kick /
  promote -> GC -> purge). Together they form the regression baseline that
  the Flutter UI layer must keep passing while it is wired up online.
- Backward compatible: legacy 3.0.1 peers interoperate unchanged because the
  new messages travel as new `Data` union variants that old peers ignore.

## Website

https://dicad.cn

## License

AGPL-3.0
