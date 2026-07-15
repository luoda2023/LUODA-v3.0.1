//! Integration tests for LUODA 3.1.1 viewer-side P2P core logic.
//!
//! These tests exercise the pure, dependency-free pieces of the viewer
//! data plane and control plane:
//!
//! - [`viewer_registry`]: invite-token issuance / consume, viewer admission,
//!   cap enforcement, promotion, kick, snapshot.
//! - [`chat_broadcast`]: peer join/leave, public/private message routing.
//! - [`viewer_direct_channel`]: host fan-out bus publish/subscribe.
//!
//! The wider network transport (rendezvous server, TCP/QUIC sockets) is
//! deliberately *not* instantiated here — those layers are covered by the
//! integration in `service.rs` and the wider app entry. The pieces below
//! are the units that decide *who* receives *what* over the P2P channel,
//! which is the part we can deterministically verify.

use std::time::Duration;

use hbb_common::message::{ChatChannel, ChatBroadcast, Message, VideoFrame};
use luoda::{
    chat_broadcast::ChatHub,
    viewer_direct_channel::{encode_message, for_session as dc_for_session, retire_session as dc_retire},
    viewer_registry::{AdmitError, Registry},
};

// ---------------------------------------------------------------------------
// viewer_registry
// ---------------------------------------------------------------------------

#[test]
fn issue_consume_token_round_trip() {
    let reg = Registry::new();
    let invite = reg.issue_token("host-A", "ses-A", None);
    let host = reg.consume_token(&invite.token);
    assert_eq!(host.as_deref(), Some("host-A"));
    let again = reg.consume_token(&invite.token);
    assert!(again.is_none());
}

#[test]
fn expired_token_is_dropped() {
    let reg = Registry::new();
    let invite = reg.issue_token("host-B", "ses-B", Some(Duration::from_millis(1)));
    std::thread::sleep(Duration::from_millis(20));
    let host = reg.consume_token(&invite.token);
    assert!(host.is_none());
}

#[test]
fn admit_viewer_succeeds_under_cap() {
    let reg = Registry::new();
    let cap = 3u32;
    reg.set_max_viewers("host-C", cap);
    for i in 0..cap {
        let vid = format!("v{i}");
        let info = reg
            .admit_viewer("host-C", &vid, &format!("Viewer {i}"), "127.0.0.1:0")
            .expect("admit under cap");
        assert_eq!(info.viewer_id, vid);
        assert!(!info.promoted);
    }
}

#[test]
fn admit_viewer_rejects_over_cap() {
    let reg = Registry::new();
    reg.set_max_viewers("host-D", 1);
    reg.admit_viewer("host-D", "v1", "V1", "127.0.0.1:1").unwrap();
    let err = reg
        .admit_viewer("host-D", "v2", "V2", "127.0.0.1:2")
        .unwrap_err();
    assert!(matches!(err, AdmitError::CapHit));
}

#[test]
fn admit_viewer_rejoin_replaces_existing() {
    let reg = Registry::new();
    reg.admit_viewer("host-E", "v1", "OldName", "127.0.0.1:1").unwrap();
    let info = reg
        .admit_viewer("host-E", "v1", "NewName", "127.0.0.1:2")
        .expect("rejoin replaces existing row");
    assert_eq!(info.display_name, "NewName");
    assert_eq!(info.endpoint, "127.0.0.1:2");
    let list = reg.list_viewers("host-E");
    assert_eq!(list.len(), 1);
}

#[test]
fn promote_and_kick() {
    let reg = Registry::new();
    reg.admit_viewer("host-F", "v1", "V1", "127.0.0.1:1").unwrap();

    let promoted = reg.promote(
        "host-F",
        &hbb_common::message::PromoteViewer { viewer_id: "v1".to_string() },
    );
    assert!(promoted);
    let list = reg.list_viewers("host-F");
    assert!(list.iter().any(|v| v.viewer_id == "v1" && v.promoted));

    let removed = reg.kick(
        "host-F",
        &hbb_common::message::KickViewer { viewer_id: "v1".to_string(), reason: "test".to_string() },
    );
    assert!(removed);
    assert!(reg.list_viewers("host-F").is_empty());
}

#[test]
fn snapshot_reports_max_viewers_and_uplink() {
    let reg = Registry::new();
    reg.set_max_viewers("host-G", 2);
    reg.admit_viewer("host-G", "v1", "V1", "127.0.0.1:1").unwrap();
    let snap = reg.snapshot("host-G", 1_500_000);
    assert_eq!(snap.max_viewers, 2);
    assert_eq!(snap.total_uplink_bps, 1_500_000);
    assert_eq!(snap.viewers.len(), 1);
}

#[test]
fn purge_clears_all_host_state() {
    let reg = Registry::new();
    reg.admit_viewer("host-H", "v1", "V1", "127.0.0.1:1").unwrap();
    reg.purge("host-H");
    let snap = reg.snapshot("host-H", 0);
    assert_eq!(snap.viewers.len(), 0);
}

// ---------------------------------------------------------------------------
// invite_code / short-code resolution
// ---------------------------------------------------------------------------

#[test]
fn resolve_short_code_then_consume_full_chain() {
    use luoda::invite_code::format_short_code;
    let reg = Registry::new();
    let invite = reg.issue_token("host-SC1", "ses-SC1", None);
    assert!(!invite.short_code.is_empty());
    // Short code (with hyphens) should resolve to the same token.
    let pretty = format_short_code(&invite.short_code);
    let resolved = reg.resolve_short_code(&pretty)
        .expect("hyphenated short code resolves");
    assert_eq!(resolved, invite.token);
    // consume_token with the canonical token should still work after resolve
    // (resolve does not burn - the spec says resolve is read-only).
    let host = reg.consume_token(&resolved);
    assert_eq!(host.as_deref(), Some("host-SC1"));
    // After consume, the short code is purged from the reverse index.
    assert!(reg.resolve_short_code(&invite.short_code).is_none());
}

#[test]
fn resolve_short_code_accepts_confusables_and_lowercase() {
    let reg = Registry::new();
    let invite = reg.issue_token("host-SC2", "ses-SC2", None);
    // Garble: lowercase + swap 0/1/V with O/I/U. Must normalise back.
    let mangled: String = invite.short_code.chars().map(|c| match c {
        '0' => 'O',
        '1' => 'I',
        'V' => 'U',
        _ => c.to_ascii_lowercase(),
    }).collect();
    let resolved = reg.resolve_short_code(&mangled)
        .expect("confusables + lowercase normalise back to canonical");
    assert_eq!(resolved, invite.token);
}

#[test]
fn resolve_short_code_rejects_expired_token() {
    let reg = Registry::new();
    let invite = reg.issue_token("host-SC3", "ses-SC3", Some(Duration::from_millis(1)));
    std::thread::sleep(Duration::from_millis(20));
    // Both paths should produce None after expiry: short-code resolve (read-only)
    // and direct consume_token (which also drops the token).
    assert!(reg.resolve_short_code(&invite.short_code).is_none());
    assert!(reg.consume_token(&invite.token).is_none());
}

#[test]
fn resolve_short_code_rejects_garbage_input() {
    let reg = Registry::new();
    reg.issue_token("host-SC4", "ses-SC4", None);
    // wrong length / out-of-alphabet / empty / hyphen collapse to None.
    assert!(reg.resolve_short_code("").is_none());
    assert!(reg.resolve_short_code("ZZZ").is_none());
    assert!(reg.resolve_short_code("!!!!!!!!!!!!").is_none());
    // 11 chars even if all-valid is still rejected (length mismatch).
    assert!(reg.resolve_short_code("J6K29P47NQX").is_none());
}

// ---------------------------------------------------------------------------
// chat_broadcast
// ---------------------------------------------------------------------------

#[test]
fn chat_public_routes_to_all_other_peers() {
    let hub = ChatHub::new();
    hub.join("host", "Host");
    hub.join("v1", "V1");
    hub.join("v2", "V2");

    let msg = ChatHub::public("host", "Host", "hello all");
    let mut targets = hub.route(&msg);
    targets.sort();
    assert_eq!(targets, vec!["v1".to_string(), "v2".to_string()]);
}

#[test]
fn chat_public_excludes_sender() {
    let hub = ChatHub::new();
    hub.join("host", "Host");
    hub.join("v1", "V1");
    let msg = ChatHub::public("v1", "V1", "hi");
    let targets = hub.route(&msg);
    assert_eq!(targets, vec!["host".to_string()]);
}

#[test]
fn chat_private_routes_only_to_target() {
    let hub = ChatHub::new();
    hub.join("host", "Host");
    hub.join("v1", "V1");
    hub.join("v2", "V2");

    let msg = ChatHub::private("v1", "V1", "host", "private note");
    let targets = hub.route(&msg);
    assert_eq!(targets, vec!["host".to_string()]);
}

#[test]
fn chat_private_to_missing_peer_is_dropped() {
    let hub = ChatHub::new();
    hub.join("host", "Host");
    let msg = ChatHub::private("host", "Host", "ghost", "lost");
    let targets = hub.route(&msg);
    assert!(targets.is_empty());
}

#[test]
fn chat_private_with_empty_to_id_drops() {
    let hub = ChatHub::new();
    hub.join("host", "Host");
    hub.join("v1", "V1");
    let msg = ChatBroadcast {
        from_id: "v1".to_string(),
        from_name: "V1".to_string(),
        channel: ChatChannel::CHAT_CHANNEL_PRIVATE.into(),
        to_id: String::new(),
        text: "no recipient".to_string(),
        sent_at: 0,
    };
    assert!(hub.route(&msg).is_empty());
}

#[test]
fn chat_leave_removes_peer_from_routing() {
    let hub = ChatHub::new();
    hub.join("host", "Host");
    hub.join("v1", "V1");

    hub.leave("v1");
    assert_eq!(hub.peer_count(), 1);

    let msg = ChatHub::public("host", "Host", "after");
    assert!(hub.route(&msg).is_empty());
}

// ---------------------------------------------------------------------------
// viewer_direct_channel
// ---------------------------------------------------------------------------

#[test]
fn direct_channel_publish_reaches_subscribers() {
    let dc = dc_for_session("test-dc-pubsub");
    let mut rx = dc.subscribe();

    let mut frame_msg = Message::new();
    frame_msg.set_video_frame(VideoFrame {
        pts: 1234,
        ..Default::default()
    });
    let bytes = encode_message(&frame_msg);
    assert!(!bytes.is_empty());
    dc.publish(bytes.clone());

    let received = rx.try_recv().expect("subscriber should receive frame");
    assert_eq!(received, bytes);
    dc_retire("test-dc-pubsub");
}

#[test]
fn direct_channel_subscriber_lagging_is_dropped() {
    let dc = dc_for_session("test-dc-lag");
    let mut slow = dc.subscribe();

    for _ in 0..200 {
        dc.publish(vec![0u8; 4]);
    }
    let res = slow.try_recv();
    assert!(res.is_err(), "lagging subscriber must not get clean frames");
    dc_retire("test-dc-lag");
}
