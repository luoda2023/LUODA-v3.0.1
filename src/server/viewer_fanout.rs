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
    tokio::{sync::mpsc, time::Instant},
};

use crate::server::chat_broadcast::{self, PeerId};

/// `Connection::inner.tx` (the non-video control mpsc) wrapped in `Arc`
/// so a single `Sender` can be cheaply cloned into the fan-out table.
pub type ControlSender = mpsc::UnboundedSender<(Instant, Arc<Message>)>;

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
            let _ = tx.send((Instant::now(), msg.clone()));
        }
    }

    /// Push a message to the host only.
    pub fn send_to_host(&self, msg: Arc<Message>) {
        if let Some(host) = &self.host_tx {
            let _ = host.send((Instant::now(), msg));
        }
    }

    /// Push a message to a single viewer id.
    pub fn send_to_viewer(&self, viewer_id: &str, msg: Arc<Message>) {
        if let Some(tx) = self.viewers.get(viewer_id) {
            let _ = tx.send((Instant::now(), msg));
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
    chat_broadcast::for_session(host_id).join(&peer_id, "host");
    g.host_peer_id = Some(peer_id);
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
                let _ = host.send((Instant::now(), msg));
                delivered += 1;
            }
            continue;
        }
        if let Some(tx) = g.viewers.get(&peer) {
            let msg = wrap_chat(cb.clone());
            let _ = tx.send((Instant::now(), msg));
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
        let _ = host.send((Instant::now(), msg.clone()));
        delivered += 1;
    }
    for (_, tx) in &g.viewers {
        let _ = tx.send((Instant::now(), msg.clone()));
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
        let _ = tx.send((Instant::now(), msg));
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
    use hbb_common::message_proto::{message, ChatChannel};
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
            ..Default::default()
        };
        let delivered = emit_chat(&sid, cb.clone());
        // host + v2 (v1 is sender, excluded by route)
        assert_eq!(delivered, 2);

        let host_msg = h_rx.try_recv().expect("host receives chat");
        assert!(host_msg.1.has_chat_broadcast());
        match host_msg.1.union.as_ref() {
            Some(message::Union::ChatBroadcast(chat)) => assert_eq!(chat.text, "hello"),
            _ => panic!("expected chat broadcast"),
        }

        let v2_msg = v2_rx.try_recv().expect("v2 receives chat");
        match v2_msg.1.union.as_ref() {
            Some(message::Union::ChatBroadcast(chat)) => assert_eq!(chat.text, "hello"),
            _ => panic!("expected chat broadcast"),
        }

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

        let vlu = ViewerListUpdate {
            viewers: Vec::new(),
            ..Default::default()
        };
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
            ..Default::default()
        };
        let delivered = emit_chat(&sid, cb);
        // Only v2 receives (host itself is excluded by `route`; v1 is gone).
        assert_eq!(delivered, 1);
        assert!(v1_rx.try_recv().is_err());
        assert!(v2_rx.try_recv().is_ok());

        retire_session(&sid);
    }

    /// 多人观看同一演示的完整会话流程：主持人开演示，3 名观众同时
    /// 加入观看；观众列表快照广播到主持人和全部观众；任一观众发言
    /// 到达主持人和其他观众（发言者本人除外）；观众全部退出后
    /// 广播不再送达（不泄漏）。
    #[test]
    fn multi_viewer_demo_session_full_flow() {
        let sid = make_session_id();
        let (h_tx, mut h_rx) = mpsc::unbounded_channel();
        let (v1_tx, mut v1_rx) = mpsc::unbounded_channel();
        let (v2_tx, mut v2_rx) = mpsc::unbounded_channel();
        let (v3_tx, mut v3_rx) = mpsc::unbounded_channel();

        // 主持人注册会话；3 名观众依次加入观看。
        register_host(&sid, "host".to_string(), h_tx);
        register_viewer(&sid, "v1", v1_tx);
        register_viewer(&sid, "v2", v2_tx);
        register_viewer(&sid, "v3", v3_tx);
        chat_broadcast::for_session(&sid).join("v1", "V1");
        chat_broadcast::for_session(&sid).join("v2", "V2");
        chat_broadcast::for_session(&sid).join("v3", "V3");

        // 1) 观众列表快照：主持人 + 3 名观众全部收到（4 个接收者）。
        let snap_delivered = emit_viewer_list_snapshot(&sid, 0);
        assert_eq!(snap_delivered, 4, "host + 3 viewers must all get the snapshot");
        assert!(h_rx.try_recv().is_ok());
        assert!(v1_rx.try_recv().is_ok());
        assert!(v2_rx.try_recv().is_ok());
        assert!(v3_rx.try_recv().is_ok());

        // 2) 观众 v2 在演示中发言：主持人 + v1 + v3 收到，v2 不收。
        let cb = ChatBroadcast {
            from_id: "v2".to_string(),
            from_name: "V2".to_string(),
            channel: ChatChannel::CHAT_CHANNEL_PUBLIC.into(),
            to_id: String::new(),
            text: "我在观看，讲得很好".to_string(),
            sent_at: 0,
            ..Default::default()
        };
        let delivered = emit_chat(&sid, cb.clone());
        assert_eq!(delivered, 3, "host + other two viewers receive the chat");
        let host_msg = h_rx.try_recv().expect("host receives viewer chat");
        match host_msg.1.union.as_ref() {
            Some(message::Union::ChatBroadcast(chat)) => {
                assert_eq!(chat.text, "我在观看，讲得很好")
            }
            _ => panic!("expected chat broadcast"),
        }
        assert!(v1_rx.try_recv().is_ok());
        assert!(v3_rx.try_recv().is_ok());
        assert!(v2_rx.try_recv().is_err(), "sender must not receive its own chat");

        // 3) 主持人更新观众列表（如踢出 v1 后刷新）：剩余接收者收到。
        unregister_viewer(&sid, "v1");
        let after = emit_viewer_list_snapshot(&sid, 0);
        assert_eq!(after, 3, "host + v2 + v3 remain");
        assert!(h_rx.try_recv().is_ok());
        assert!(v2_rx.try_recv().is_ok());
        assert!(v3_rx.try_recv().is_ok());
        assert!(v1_rx.try_recv().is_err(), "removed viewer gets nothing");

        // 4) 全部观众退出后，广播不再送达（无泄漏）。
        unregister_viewer(&sid, "v2");
        unregister_viewer(&sid, "v3");
        let empty = emit_viewer_list_snapshot(&sid, 0);
        assert_eq!(empty, 1, "only host remains");
        assert!(h_rx.try_recv().is_ok());
        assert!(v2_rx.try_recv().is_err());
        assert!(v3_rx.try_recv().is_err());

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
        m.set_viewer_list_update(ViewerListUpdate {
            viewers: Vec::new(),
            ..Default::default()
        });
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
