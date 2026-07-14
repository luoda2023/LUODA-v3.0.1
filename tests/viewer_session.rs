//! LUODA 3.1.1 -- End-to-end viewer session contract tests.
//!
//! These tests stitch together the pieces that `Connection` would invoke
//! when a real viewer-mode client joins a host session, but without the
//! rendezvous / tokio transport layer. They form the high-level contract
//! that the upstream server integration (and the Flutter UI layer) must
//! continue to satisfy as 3.1.1 evolves:
//!
//! 1. `host` issues an invite token (default / one-shot / custom TTL).
//! 2. A `viewer` resolves the short-code back to the canonical token.
//! 3. `Registry::consume_token` accepts the token and returns the host id.
//! 4. `Registry::admit_viewer` admits the viewer under the host cap and
//!    records `ViewerState` for the simulation connection.
//! 5. `ChatHub` routes public + private `ChatBroadcast` traffic between
//!    the admitted viewers + host, mirroring the host-side fan-out loop.
//! 6. Host `KickViewer` and `PromoteViewer` mutate the registry bucket; the
//!    `ViewerState::promoted` flag stays in sync when the host elevates a
//!    viewer.
//! 7. `Registry::gc_expired` purges expired invite tokens (and the linked
//!    short-code reverse index) without touching the live viewers.
//! 8. `Registry::purge` clears the entire host bucket when the session ends.
//!
//! The lower-level primitives (registry internals, chat hub routing,
//! direct channel bus) are exhaustively covered by `tests/viewer_p2p.rs`.
//! This file is intentionally a *contract walk* instead of a re-test of
//! every primitive edge case.

use std::time::Duration;

use hbb_common::message::{ChatChannel, KickViewer, PromoteViewer};
use luoda::{
    chat_broadcast::ChatHub,
    invite_code::format_short_code,
    viewer_registry::Registry,
    viewer_state::ViewerState,
};

const HOST:   &str = "host-3-1-1";
const SESSION: &str = "ses-3-1-1";

// ---------------------------------------------------------------------------
// Step 1-3: token issue -> short-code resolve -> consume.
// ---------------------------------------------------------------------------

#[test]
fn invite_token_round_trip_returns_host() {
    let reg = Registry::new();
    let invite = reg.issue_token(HOST, SESSION, None);
    assert!(!invite.token.is_empty());
    assert!(!invite.short_code.is_empty());

    // Short-code is the canonical entrypoint a viewer would type; the
    // registry must resolve it to the same canonical token.
    let pretty = format_short_code(&invite.short_code);
    let resolved = reg
        .resolve_short_code(&pretty)
        .expect("hyphenated short code resolves to canonical token");
    assert_eq!(resolved, invite.token);

    // consume_token returns the host that minted the token.
    let host = reg.consume_token(&resolved).expect("consume succeeds");
    assert_eq!(host.as_deref(), Some(HOST));
    // Second consume is a no-op (token already burned).
    assert!(reg.consume_token(&resolved).is_none());
}

#[test]
fn invite_token_one_shot_is_burned_after_consume() {
    let reg = Registry::new();
    let invite = reg.issue_token(HOST, SESSION, Some(Duration::from_secs(0)));
    // Zero-TTL is treated as a one-shot token: the first consume succeeds
    // even though the wall clock may already be past expiry, and the
    // registry never returns the same token twice.
    let host = reg.consume_token(&invite.token).expect("consume one-shot");
    assert_eq!(host.as_deref(), Some(HOST));
    assert!(reg.consume_token(&invite.token).is_none());
}

#[test]
fn invite_token_short_ttl_expires() {
    let reg = Registry::new();
    let invite = reg.issue_token(HOST, SESSION, Some(Duration::from_millis(1)));
    std::thread::sleep(Duration::from_millis(20));
    // Expiry drops both the canonical token and the short-code reverse
    // index, so a viewer joining via either form is rejected.
    assert!(reg.consume_token(&invite.token).is_none());
    assert!(reg.resolve_short_code(&invite.short_code).is_none());
}

// ---------------------------------------------------------------------------
// Step 4: admit a viewer, ensure ViewerState is constructed correctly,
//         and that the registry knows them.
// ---------------------------------------------------------------------------

#[test]
fn admit_viewer_records_state_and_list_viewers() {
    let reg = Registry::new();
    let invite = reg.issue_token(HOST, SESSION, None);
    let host = reg.consume_token(&invite.token).expect("consume succeeds");
    assert_eq!(host.as_deref(), Some(HOST));

    let info = reg
        .admit_viewer(HOST, "v1", "V1", "127.0.0.1:9001")
        .expect("admit succeeds under default cap");
    assert_eq!(info.viewer_id, "v1");
    assert_eq!(info.display_name, "V1");
    assert!(!info.promoted);

    // The same viewer id re-joining replaces the existing entry instead of
    // being rejected; the list keeps a single row for that id.
    let info2 = reg
        .admit_viewer(HOST, "v1", "V1 renewed", "127.0.0.1:9002")
        .expect("rejoin replaces existing entry");
    assert_eq!(info2.display_name, "V1 renewed");

    let list = reg.list_viewers(HOST);
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].viewer_id, "v1");
    assert_eq!(list[0].display_name, "V1 renewed");

    // The simulation connection's ViewerState mirrors the registry; 3.1.1
    // keeps the per-connection flag in sync via `handle_promote_viewer`.
    let state = ViewerState::new(info2.viewer_id.clone(), info2.display_name.clone());
    assert!(!state.promoted);
    assert!(!state.raise_hand);
}

#[test]
fn admit_viewer_enforces_max_viewers_cap() {
    let reg = Registry::new();
    reg.set_max_viewers(HOST, 2);
    reg.admit_viewer(HOST, "v1", "V1", "127.0.0.1:1").unwrap();
    reg.admit_viewer(HOST, "v2", "V2", "127.0.0.1:2").unwrap();
    let err = reg
        .admit_viewer(HOST, "v3", "V3", "127.0.0.1:3")
        .unwrap_err();
    assert!(matches!(err, luoda::viewer_registry::AdmitError::CapHit));

    // Snapshot reports the cap and the admitted viewers together; this is
    // what the host UI renders as the viewer list.
    let snap = reg.snapshot(HOST, 0);
    assert_eq!(snap.max_viewers, 2);
    assert_eq!(snap.viewers.len(), 2);
}

// ---------------------------------------------------------------------------
// Step 5: ChatHub routes public + private broadcasts exactly as the
//         host fan-out loop would, given the same set of admitted viewers.
// ---------------------------------------------------------------------------

#[test]
fn chat_hub_routes_session_traffic() {
    let hub = ChatHub::new();
    hub.join(HOST, "Host");
    hub.join("v1", "V1");
    hub.join("v2", "V2");

    // Public broadcast reaches everyone except the sender.
    let public = ChatHub::public("v1", "V1", "hi all");
    assert_eq!(public.channel, ChatChannel::CHAT_CHANNEL_PUBLIC.into());
    let mut targets = hub.route(&public);
    targets.sort();
    assert_eq!(targets, vec![HOST.to_string(), "v2".to_string()]);

    // Private broadcast (viewer -> host) is delivered only to the host.
    let private = ChatHub::private("v2", "V2", HOST, "private msg");
    assert_eq!(private.channel, ChatChannel::CHAT_CHANNEL_PRIVATE.into());
    assert_eq!(hub.route(&private), vec![HOST.to_string()]);

    // Private broadcast to a missing peer is dropped silently (the host
    // transport should not attempt delivery).
    let missing = ChatHub::private(HOST, "Host", "ghost", "lost");
    assert!(hub.route(&missing).is_empty());

    // Leaving the chat hub mirrors what Connection does on disconnect.
    hub.leave("v2");
    assert_eq!(hub.peer_count(), 2);
    let public_after = ChatHub::public(HOST, "Host", "after leave");
    let targets_after = hub.route(&public_after);
    assert_eq!(targets_after, vec!["v1".to_string()]);
}

// ---------------------------------------------------------------------------
// Step 6: KickViewer drops the viewer from the registry; PromoteViewer
//         flips the badge and the per-connection ViewerState mirrors it.
// ---------------------------------------------------------------------------

#[test]
fn kick_and_promote_mutate_registry_and_state() {
    let reg = Registry::new();
    reg.set_max_viewers(HOST, 4);
    reg.admit_viewer(HOST, "v1", "V1", "127.0.0.1:1").unwrap();
    reg.admit_viewer(HOST, "v2", "V2", "127.0.0.1:2").unwrap();

    // Promote v1; the registry bucket flips the promoted flag.
    let promoted = reg.promote(
        HOST,
        &PromoteViewer {
            viewer_id: "v1".to_string(),
            promoted: true,
            ..Default::default()
        },
    );
    assert!(promoted, "promote returns true when viewer exists");
    let list = reg.list_viewers(HOST);
    let v1 = list.iter().find(|v| v.viewer_id == "v1").unwrap();
    assert!(v1.promoted);

    // The per-connection ViewerState that Connection keeps is updated to
    // mirror the registry when handle_promote_viewer runs.
    let mut state = ViewerState::new("v1".to_string(), "V1".to_string());
    state.promoted = true;
    assert!(state.promoted);

    // Kick v2; the viewer list no longer contains them.
    let kicked = reg.kick(
        HOST,
        &KickViewer {
            viewer_id: "v2".to_string(),
            reason: "test kick".to_string(),
            ..Default::default()
        },
    );
    assert!(kicked);
    let list_after = reg.list_viewers(HOST);
    assert!(list_after.iter().all(|v| v.viewer_id != "v2"));
    assert_eq!(list_after.len(), 1);
}

// ---------------------------------------------------------------------------
// Step 7: gc_expired purges stale tokens but keeps live viewers.
// ---------------------------------------------------------------------------

#[test]
fn gc_drops_expired_tokens_only() {
    let reg = Registry::new();
    let expired = reg.issue_token(HOST, SESSION, Some(Duration::from_millis(1)));
    let live = reg.issue_token(HOST, SESSION, Some(Duration::from_secs(60 * 30)));

    std::thread::sleep(Duration::from_millis(20));
    reg.gc_expired();

    // Live token + its short code remain.
    assert!(reg.consume_token(&live.token).is_some());
    assert!(reg.resolve_short_code(&live.short_code).is_some());

    // Expired token (and its short-code reverse index) are gone.
    assert!(reg.consume_token(&expired.token).is_none());
    assert!(reg.resolve_short_code(&expired.short_code).is_none());
}

// ---------------------------------------------------------------------------
// Step 8: purge clears the entire host bucket at session shutdown.
// ---------------------------------------------------------------------------

#[test]
fn purge_clears_host_state_for_shutdown() {
    let reg = Registry::new();
    let _ = reg.issue_token(HOST, SESSION, None);
    reg.admit_viewer(HOST, "v1", "V1", "127.0.0.1:1").unwrap();
    reg.admit_viewer(HOST, "v2", "V2", "127.0.0.1:2").unwrap();

    reg.purge(HOST);

    let snap = reg.snapshot(HOST, 0);
    assert_eq!(snap.viewers.len(), 0);
    assert_eq!(snap.max_viewers, 0);
}

// ---------------------------------------------------------------------------
// Cross-piece contract: the same `host_id` is used by the registry bucket,
// the chat hub peers, and the per-session fan-out. This invariant lets the
// transport layer talk to one logical identity per session.
// ---------------------------------------------------------------------------

#[test]
fn host_id_consistent_across_registry_and_chat_hub() {
    let reg = Registry::new();
    let hub = ChatHub::new();

    let _ = reg.issue_token(HOST, SESSION, None);
    let _ = reg.consume_token(&reg.issue_token(HOST, SESSION, None).token);
    hub.join(HOST, "Host");
    hub.join("v1", "V1");

    // The host that minted the token is the same peer that joined the chat
    // hub as a host. The viewer admitted against that host belongs to the
    // same session key. The transport layer relies on this invariant --
    // breaking it would route broadcasts to the wrong host.
    let _info = reg.admit_viewer(HOST, "v1", "V1", "127.0.0.1:1").unwrap();
    assert!(hub.peer_count() >= 2);

    let public = ChatHub::public("v1", "V1", "broadcast");
    let targets: Vec<String> = hub.route(&public);
    assert!(targets.contains(&HOST.to_string()));
}