//! LUODA 3.1.1 — Per-session viewer fan-out.
//! -------------------------------------------------------------------------
//! While [`crate::server::chat_broadcast::ChatHub`] only computes *who*
//! should receive a message, this module actually ships the bytes to the
//! right connection. Every viewer connection registers its control
//! `Sender` (the same mpsc channel that `Connection::inner.send` pushes
//! into) when it joins a session; the host connection registers its own
//! `Sender` the first time it issues a viewer-list-affecting action.
//!
//! On every relevant event (`{handle,emit}_*_*` in `Connection`), the
//! fan-out hub is given the fully-built `Message`, which it forwards to
//! the registered mpsc senders. The downstream `Connection` task picks
//! the message up and writes it to its TCP / QUIC stream — no extra
//! thread is spawned here.
//!
//! This is deliberately a single `Mutex<HashMap<...>>` per session: chat
//! and viewer-list rate are tiny (sub-second × sub-8) for the 3.1.1
//! target of 8 viewers per host; contention is essentially nil.

use std::{collections::HashMap, sync::{Arc, Mutex}};

use hbb_common::{
    message_proto::{ChatBroadcast, ChatChannel, Message, ViewerListUpdate},
    tokio::sync::mpsc,
};

use crate::server::chat_broadcast::{self, PeerId};

/// `Connection::inner.tx` (the non-video control mpsc) wrapped in `Arc`
/// so a single `Sender` can be cheaply cloned into the fan-out table.
pub type ControlSender = mpsc::UnboundedSender<(std::time::Instant, Arc<Message>)>;

/// Per-host-session fan-out state. One entry per active host session; the
/// entry is created lazily by the first `register_*` and retired by the
/// session-shutdown hooks (`retire_session`).
#[derive(Default)]
pub struct SessionFanout {
    /// Sender for the host's control connection. `None` until the host
    /// first interacts with the viewer system.
    pub host_tx: Option<ControlSender>,
    /// `viewer_id -> control sender` for every admitted viewer on this
    /// session. Re-uses the same channel `Connection::inner` uses
    /// internally, so no extra forwarder task is needed.
    pub viewers: HashMap<PeerId, ControlSender>,
    /// Cached lookup of which `PeerId` represents the host inside the
    /// shared [`chat_broadcast::ChatHub`]. Stored here so fan-out can map
    /// a hub-routed peer id back to the host's control channel.
    pub host_peer_id: Option<PeerId>,
}

impl SessionFanout {
    pub fn new() -> Self {
        Self::default()
    }

    /// Push a message to every registered viewer (host excluded). Used by
    /// `emit_viewer_list_update` so the host UI update is delivered
    /// separately via `host_tx`.
    pub fn broadcast_to_viewers(&self, msg: Arc<Message>) {
        for (_, tx) in &self.viewers {
            let _ = tx.send((std::time::Instant::now(), msg.clone()));
        }
    }

    /// Push a message to the host only.
    pub fn send_to_host(&self, msg: Arc<Message>) {
        if let Some(host) = &self.host_tx {
            let _ = host.send((std::time::Instant::now(), msg));
        }
    }

    /// Push a message to a single viewer id.
    pub fn send_to_viewer(&self, viewer_id: &str, msg: Arc<Message>) {
        if let Some(tx) = self.viewers.get(viewer_id) {
            let _ = tx.send((std::time::Instant::now(), msg));
        }
    }
}

lazy_static::lazy_static! {
    /// `host_id -> SessionFanout`. The session id is the same
    /// key used by [`chat_broadcast::for_session`] and
    /// [`viewer_registry::REGISTRY`] (the controlled peer's id).
    pub static ref SESSIONS: Mutex<HashMap<String, Arc<Mutex<SessionFanout>>>> =
        Mutex::new(HashMap::new());
}

/// Get-or-create the per-session fan-out table.
pub fn for_session(host_id: &str) -> Arc<Mutex<SessionFanout>> {
    let mut m = SESSIONS.lock().unwrap();
    m.entry(host_id.to_owned())
        .or_insert_with(|| Arc::new(Mutex::new(SessionFanout::new())))
        .clone()
}

/// Drop the per-session table. Called when the host session ends so we
/// do not leak viewer senders after the controlled peer disconnects.
pub fn retire_session(host_id: &str) {
    let _ = SESSIONS.lock().unwrap().remove(host_id);
}

/// Convenience wrapper: register a host-side control sender. Idempotent
/// (re-registration overwrites the previous sender, which is fine — a
/// reconnecting host should refresh the channel).
pub fn register_host(host_id: &str, peer_id: PeerId, tx: ControlSender) {
    let f = for_session(host_id);
    let mut g = f.lock().unwrap();
    g.host_tx = Some(tx);
    g.host_peer_id = Some(peer_id);
    chat_broadcast::for_session(host_id).join(&peer_id, "host");
}

/// Unregister the host sender (e.g. when the controlling peer
/// disconnects). The viewers' senders remain until they themselves are
/// removed by `unregister_viewer` / `retire_session`.
pub fn unregister_host(host_id: &str) {
    let f = for_session(host_id);
    let mut g = f.lock().unwrap();
    if let Some(peer_id) = g.host_peer_id.take() {
        chat_broadcast::for_session(host_id).leave(&peer_id);
    }
    g.host_tx = None;
}

/// Register a viewer's control sender. Idempotent.
pub fn register_viewer(host_id: &str, viewer_id: &str, tx: ControlSender) {
    let f = for_session(host_id);
    let mut g = f.lock().unwrap();
    g.viewers.insert(viewer_id.to_owned(), tx);
}

/// Drop a viewer from the fan-out table. Idempotent.
pub fn unregister_viewer(host_id: &str, viewer_id: &str) {
    let f = for_session(host_id);
    let mut g = f.lock().unwrap();
    g.viewers.remove(viewer_id);
}

/// Push a `ChatBroadcast` to every relevant peer on the session by
/// consulting [`chat_broadcast::ChatHub::route`] and then walking the
/// fan-out table. The sender itself is excluded by `route`. Returns the
/// number of recipients actually delivered to (i.e. with a registered
/// `ControlSender`).
pub fn emit_chat(host_id: &str, cb: ChatBroadcast) -> usize {
    let hub = chat_broadcast::for_session(host_id);
    let recipients = hub.route(&cb);
    let f = for_session(host_id);
    let g = f.lock().unwrap();
    let mut delivered = 0usize;
    for peer in recipients {
        if Some(&peer) == g.host_peer_id.as_ref() {
            if let Some(host) = &g.host_tx {
                let msg = wrap_chat(cb.clone());
                let _ = host.send((std::time::Instant::now(), msg));
                delivered += 1;
            }
            continue;
        }
        if let Some(tx) = g.viewers.get(&peer) {
            let msg = wrap_chat(cb.clone());
            let _ = tx.send((std::time::Instant::now(), msg));
            delivered += 1;
        }
    }
    delivered
}

/// Push a `ViewerListUpdate` to the host and every registered viewer.
/// Useful for participant-list UI sync after a join / leave / promote /
/// kick event. Returns the total recipient count.
pub fn emit_viewer_list_update(host_id: &str, vlu: ViewerListUpdate) -> usize {
    let f = for_session(host_id);
    let g = f.lock().unwrap();
    let mut delivered = 0usize;
    let msg = wrap_viewer_list_update(vlu.clone());
    if let Some(host) = &g.host_tx {
        let _ = host.send((std::time::Instant::now(), msg.clone()));
        delivered += 1;
    }
    for (_, tx) in &g.viewers {
        let _ = tx.send((std::time::Instant::now(), msg.clone()));
        delivered += 1;
    }
    delivered
}

/// Push an opaque `Message` to a single viewer (e.g. kick / promote
/// acknowledgement). Returns true if delivered.
pub fn emit_to_viewer(host_id: &str, viewer_id: &str, msg: Arc<Message>) -> bool {
    let f = for_session(host_id);
    let g = f.lock().unwrap();
    if let Some(tx) = g.viewers.get(viewer_id) {
        let _ = tx.send((std::time::Instant::now(), msg));
        true
    } else {
        false
    }
}

fn wrap_chat(cb: ChatBroadcast) -> Arc<Message> {
    let mut m = Message::new();
    m.set_chat_broadcast(cb);
    Arc::new(m)
}

fn wrap_viewer_list_update(vlu: ViewerListUpdate) -> Arc<Message> {
    let mut m = Message::new();
    m.set_viewer_list_update(vlu);
    Arc::new(m)
}


/// Build a fresh `ViewerListUpdate` from the viewer registry and push it
/// to the host + every registered viewer via [`emit_viewer_list_update`].
/// `total_uplink_bps` is whatever the caller last observed from the
/// direct-channel uplink meter; 0 is fine for the pure-control case.
pub fn emit_viewer_list_snapshot(host_id: &str, total_uplink_bps: u64) -> usize {
    let vlu = crate::server::viewer_registry::REGISTRY.snapshot(host_id, total_uplink_bps);
    emit_viewer_list_update(host_id, vlu)
}
#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::message_proto::ChatChannel;
    use hbb_common::tokio::sync::mpsc;
    use std::time::Instant;

    fn make_session_id() -> String {
        format!("test-session-{}", uuid::Uuid::new_v4())
    }

    /// Smoke test: register a host + 2 viewers, fire a public chat, every
    /// recipient receives a `Message` whose `chat_broadcast` payload
    /// equals the one we emitted, and the sender receives nothing.
    #[test]
    fn emit_chat_public_reaches_host_and_viewers_only() {
        let sid = make_session_id();
        let (h_tx, mut h_rx) = mpsc::unbounded_channel();
        let (v1_tx, mut v1_rx) = mpsc::unbounded_channel();
        let (v2_tx, mut v2_rx) = mpsc::unbounded_channel();

        register_host(&sid, "host".to_string(), h_tx);
        register_viewer(&sid, "v1", v1_tx);
        register_viewer(&sid, "v2", v2_tx);

        // Chat hub does not auto-join viewers — register_viewer must call
        // chat_broadcast hub join only for host (the viewer join is done
        // by Connection::handle_join_as_viewer in production). Mirror that
        // here so route() can see v1 / v2.
        chat_broadcast::for_session(&sid).join("v1", "V1");
        chat_broadcast::for_session(&sid).join("v2", "V2");

        let cb = ChatBroadcast {
            from_id: "v1".to_string(),
            from_name: "V1".to_string(),
            channel: ChatChannel::CHAT_CHANNEL_PUBLIC.into(),
            to_id: String::new(),
            text: "hello".to_string(),
            sent_at: 0,
        };
        let delivered = emit_chat(&sid, cb.clone());
        // host + v2 (v1 is sender, excluded by route)
        assert_eq!(delivered, 2);

        let host_msg = h_rx.try_recv().expect("host receives chat");
        assert!(host_msg.1.has_chat_broadcast());
        assert_eq!(host_msg.1.get_chat_broadcast().text, "hello");

        let v2_msg = v2_rx.try_recv().expect("v2 receives chat");
        assert_eq!(v2_msg.1.get_chat_broadcast().text, "hello");

        // Sender (v1) must not receive its own message.
        assert!(v1_rx.try_recv().is_err());

        retire_session(&sid);
    }

    /// `emit_viewer_list_update` sends to host + every viewer exactly once.
    #[test]
    fn emit_viewer_list_update_reaches_all_peers() {
        let sid = make_session_id();
        let (h_tx, mut h_rx) = mpsc::unbounded_channel();
        let (v1_tx, mut v1_rx) = mpsc::unbounded_channel();
        let (v2_tx, mut v2_rx) = mpsc::unbounded_channel();

        register_host(&sid, "host".to_string(), h_tx);
        register_viewer(&sid, "v1", v1_tx);
        register_viewer(&sid, "v2", v2_tx);

        let vlu = ViewerListUpdate { viewers: Vec::new() };
        let delivered = emit_viewer_list_update(&sid, vlu);
        assert_eq!(delivered, 3);

        assert!(h_rx.try_recv().is_ok());
        assert!(v1_rx.try_recv().is_ok());
        assert!(v2_rx.try_recv().is_ok());

        retire_session(&sid);
    }

    /// Unregistering a viewer drops it from future deliveries.
    #[test]
    fn unregister_viewer_skips_dropped_sender() {
        let sid = make_session_id();
        let (h_tx, _h_rx) = mpsc::unbounded_channel();
        let (v1_tx, mut v1_rx) = mpsc::unbounded_channel();
        let (v2_tx, mut v2_rx) = mpsc::unbounded_channel();

        register_host(&sid, "host".to_string(), h_tx);
        register_viewer(&sid, "v1", v1_tx);
        register_viewer(&sid, "v2", v2_tx);
        chat_broadcast::for_session(&sid).join("v1", "V1");
        chat_broadcast::for_session(&sid).join("v2", "V2");

        unregister_viewer(&sid, "v1");

        let cb = ChatBroadcast {
            from_id: "host".to_string(),
            from_name: "host".to_string(),
            channel: ChatChannel::CHAT_CHANNEL_PUBLIC.into(),
            to_id: String::new(),
            text: "after kick".to_string(),
            sent_at: 0,
        };
        let delivered = emit_chat(&sid, cb);
        // Only v2 receives (host itself is excluded by `route`; v1 is gone).
        assert_eq!(delivered, 1);
        assert!(v1_rx.try_recv().is_err());
        assert!(v2_rx.try_recv().is_ok());

        retire_session(&sid);
    }

    /// `emit_to_viewer` delivers only to the targeted viewer.
    #[test]
    fn emit_to_viewer_targets_single_peer() {
        let sid = make_session_id();
        let (h_tx, mut h_rx) = mpsc::unbounded_channel();
        let (v1_tx, mut v1_rx) = mpsc::unbounded_channel();
        let (v2_tx, mut v2_rx) = mpsc::unbounded_channel();
        register_host(&sid, "host".to_string(), h_tx);
        register_viewer(&sid, "v1", v1_tx);
        register_viewer(&sid, "v2", v2_tx);

        let mut m = Message::new();
        m.set_viewer_list_update(ViewerListUpdate { viewers: Vec::new() });
        let arc = Arc::new(m);

        assert!(emit_to_viewer(&sid, "v2", arc.clone()));
        assert!(v1_rx.try_recv().is_err());
        assert!(v2_rx.try_recv().is_ok());
        assert!(h_rx.try_recv().is_err());

        // Unknown viewer id is reported as not delivered.
        assert!(!emit_to_viewer(&sid, "ghost", arc));

        retire_session(&sid);
    }
}
