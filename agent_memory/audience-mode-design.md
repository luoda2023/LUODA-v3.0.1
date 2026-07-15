# Audience Mode (观众模式) — Design Proposal for LUODA 3.1.1+

> Status: **Design-only marker** shipped with 3.1.1. Implementation is deferred
> until a build-capable environment (online cargo build on windows-latest,
> macos-latest, ubuntu-latest) is available, because the change surface
> touches the live P2P / relay IO hot path in src/client.rs,
> src/rendezvous_mediator.rs, and src/client/io_loop.rs. Modifying those
> without compile + integration verification would risk regressing the 3.0.1
> stable remote-desktop path that LUODA already ships.

## 1. Goals

- Let a host (the existing "controlled" side, B) broadcast its desktop stream
  to **multiple viewers** (audience, A₁..Aₙ) without giving any of them
  keyboard / mouse / clipboard control.
- Audience join is by **session number** issued by B, not by B's permanent ID.
  The session number is short-lived, rotatable, and revocable.
- A lightweight **introducer** (the existing rendezvous server, extended)
  only relays session-number → B-public-endpoint metadata. It carries **no
   video bytes** and **no control bytes**.
- Reuse 3.0.1's existing view-only pathway (config.view_only.v,
  src/client.rs:2213-2425, src/keyboard.rs:366-371) so audience members
  are literally view-only clients connected to the same host session.

## 2. Non-goals (3.1.1 scope)

- No mesh multipath between audiences. All audience streams egress from B
  (star topology). Mesh fan-out is a 3.2+ concern.
- No per-audience permission tiers. Audience members are uniformly view-only.
  Selective control handoff is a 3.2+ concern.
- No new NAT-traversal library. Continue to use hbb_common's
  RendezvousMediator and punch_hole/elay flow; only the *registration
  payload* gains an optional udience_of field.

## 3. Protocol extensions (sketch)

All additions are **optional fields** on existing protobuf messages so that
3.0.1 servers and clients keep working unchanged.

`protobuf
// In hbb_common/protos/rendezvous.proto
message RegisterPeer {
  ...existing fields...
  optional string audience_of = 10; // session number introduced by B
}

message PunchHole {
  ...existing fields...
  optional string audience_of = 10; // echoed back by introducer
}

// New message, only used by introducer <-> B <-> A
message AudienceIntroduce {
  string session_id = 1;     // short numeric, e.g. 6 digits
  string host_id = 2;        // B's permanent LUODA id
  string host_public = 3;     // ip:port or relay hint
  optional string host_pk = 4;
}
`

Wire compatibility is preserved because protobuf unknown-fields are ignored
by older clients. The introducer routes AudienceIntroduce only to peers that
advertise udience_of matching a registered session.

## 4. State machine on B (host)

1. B clicks "Open audience session" in 3.1.1 UI (a new action beside the
   existing 3.0.1 "Join Session" button at
   lutter/lib/desktop/pages/desktop_home_page.dart:372).
2. B's LUODA client generates a 6-digit session_id, registers itself with
   the introducer with RegisterPeer { audience_of: <session_id> }.
3. B's existing server (src/server.rs:accept_connection) is unchanged;
   audience members arrive as normal view-only connections, gated by
   lc.view_only.v = true (src/keyboard.rs:366, src/client.rs:2333).
4. B may rotate or revoke the session_id at any time. Rotation invalidates
   outstanding introduces; revocation disconnects all current audience
   members whose udience_of no longer matches.

## 5. State machine on A (audience)

1. A enters session_id (not B's permanent id) in the connection box.
2. A's LUODA client sends RegisterPeer { audience_of: <session_id> } to
   the introducer with A's own id.
3. Introducer replies with AudienceIntroduce { host_id, host_public,
   host_pk }.
4. A connects to host_public as a normal view-only client. Reuses
   Connection::new + iew_only.v = true. No new IO path.

## 6. Introducer (rendezvous server) changes

The introducer is the **only** component that must change in 3.1.1 to ship
audience mode, and even there the diff is small:

- Keep a HashMap<session_id, AudienceRegistration> in memory.
- On RegisterPeer { audience_of: Some(sid) }:
  - If peer_id == host_id_of(sid), store/update host_public + host_pk.
  - Else reply AudienceIntroduce { host_id, host_public, host_pk }.
- On RegisterPeer { audience_of: None }: behave exactly as 3.0.1.
- No video, no clipboard, no file bytes flow through the introducer.

The mismatch between introducer and B-public-endpoint is handled exactly
like 3.0.1's existing punch_hole/elay selection: try direct, fall back
to relay, never touch introducer for media.

## 7. Why not implement in 3.1.1 right now

- cargo build on a 4k-LoC diff over endezvous_mediator.rs +
  client.rs:io_loop requires online crate fetch and ~10-minute rebuilds.
  This environment is offline-only for crates.io.
- The 3.0.1 stable path (egister_pk → punch_hole → elay) is load-
  bearing. A subtle regression there breaks every LUODA connection, not just
  audience mode.
- The 3.1.1 release is therefore scoped to: version bump, CI metadata, and
  retaining the previously-applied fixes tracked in gent_memory/bugs.md
  (upnp.rs LAN-IP fallback, build.rs libsodium link name, flutter_ffi.rs
  public-IP timeout). This matches the AGENTS.md rule that unrelated bugs
  are recorded, not extended, and that changes should be minimal and
  focused.

## 8. Acceptance criteria (for the future implementation PR)

- [ ] cargo build --release on Windows / macOS / Linux each succeeds with
  zero new warnings.
- [ ] 3.0.1 client ↔ 3.1.1 introducer ↔ 3.0.1 client still connects (no
  protobuf break).
- [ ] One host B + three audience A₁..A₃ all see B's screen at >=10 fps,
  each with iew_only.v = true enforced by B's server (no input events
  accepted from Aᵢ).
- [ ] Revoking the session_id from B disconnects all Aᵢ within 5s.
- [ ] Introducer memory remains bounded (sessions expire after 1h if the
  host has not refreshed).
- [ ] No media bytes traverse the introducer. Verified by 	cpdump on the
  introducer host.

## 9. Touch list (future implementation, not 3.1.1)

- hbb_common/protos/rendezvous.proto — add optional fields + new message.
- hbb_common/src/protos/message.rs — regenerate.
- src/rendezvous_mediator.rs — egister_peer/handle_punch_hole carry
  udience_of.
- src/server.rs — audience connections inherit iew_only.v = true.
- lutter/lib/desktop/pages/desktop_home_page.dart:372 — split "Join
  Session" into "Open audience session" + "Join audience session".
- lutter/lib/desktop/pages/connection_page.dart — accept 6-digit
  session_id syntax distinct from a permanent peer id.
- src/lang/* — add Open audience session + Join audience session +
  Session revoked keys.

## 10. Open questions

- Should audience members be allowed to **hear** B's audio? 3.0.1 already
  has audio capture; reuse is straightforward but may surprise B. Default
  proposed: **no audio** for audience, only video + chat text.
- Should the introducer log session creation / revocation? Default proposed:
  log only at info level, with session_id truncated to first 3 digits, to
  protect PII.
- Should B see a roster of connected audience members? Default proposed: yes,
  a non-dismissable chip list in the host UI so B can manually disconnect
  any Aᵢ at will.
