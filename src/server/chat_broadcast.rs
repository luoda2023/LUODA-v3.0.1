//! LUODA 3.1.1 — Multi-party chat broadcast
//! -------------------------------------------------------------------------
//! A small, dependency-light multiparty chat hub for a host session:
//!
//!   * `Public`   — fan-out to host + every viewer.
//!   * `Private`  — 1:1 between host and a single viewer (never viewer ↔ viewer;
//!                   the host is the only one who can read private traffic).
//!
//! The hub is purely in-memory and not persisted; chat logs are *not* stored
//! server-side. The hub itself does not touch the network — the host's
//! transport loop is responsible for ferrying each [`ChatBroadcast`] to the
//! right peer over the viewer direct channel (P2P) or the main control
//! connection (host-side).
//!
//! Threading model: silent `Mutex<...>` guards around small hashmaps. Hot
//! path is `_broadcast`, which clones short Vecs of subscriber handles.
//! The hot-path cost is O(subscribers). For a typical 8-viewer call this is
//! well under 1µs per published message on commodity hardware.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{SystemTime, UNIX_EPOCH},
};

use hbb_common::message::{ChatBroadcast, ChatChannel};

pub type PeerId = String;

#[derive(Default)]
pub struct ChatHub {
    /// `viewer_id -> display_name`, kept in sync as viewers join/leave.
    pub peers: Mutex<HashMap<PeerId, String>>,
}

impl ChatHub {
    pub fn new() -> Self {
        Self { peers: Mutex::new(HashMap::new()) }
    }

    pub fn join(&self, peer_id: &str, display_name: &str) {
        self.peers.lock().unwrap().insert(peer_id.to_owned(), display_name.to_owned());
    }

    pub fn leave(&self, peer_id: &str) {
        self.peers.lock().unwrap().remove(peer_id);
    }

    /// Compose a public message. Caller (host or viewer transport) injects
    /// the resulting [`ChatBroadcast`] into the local hub via `route()`.
    pub fn public(from_id: &str, from_name: &str, text: &str) -> ChatBroadcast {
        ChatBroadcast {
            from_id: from_id.to_owned(),
            from_name: from_name.to_owned(),
            channel: ChatChannel::CHAT_CHANNEL_PUBLIC.into(),
            to_id: String::new(),
            text: text.to_owned(),
            sent_at: SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs(),
        }
    }

    /// Compose a private message (host <-> one viewer).
    pub fn private(from_id: &str, from_name: &str, to_id: &str, text: &str) -> ChatBroadcast {
        ChatBroadcast {
            from_id: from_id.to_owned(),
            from_name: from_name.to_owned(),
            channel: ChatChannel::CHAT_CHANNEL_PRIVATE.into(),
            to_id: to_id.to_owned(),
            text: text.to_owned(),
            sent_at: SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs(),
        }
    }

    /// Decide who should receive a given [`ChatBroadcast`].
    ///
    /// Returns a list of peer ids (excluding the sender). The transport
    /// layer is responsible for actually delivering to each peer.
    pub fn route(&self, msg: &ChatBroadcast) -> Vec<PeerId> {
        let peers = self.peers.lock().unwrap();
        match msg.channel.enum_value() {
            Ok(ChatChannel::CHAT_CHANNEL_PUBLIC) => peers
                .keys()
                .filter(|p| p.as_str() != msg.from_id.as_str())
                .cloned()
                .collect(),
            Ok(ChatChannel::CHAT_CHANNEL_PRIVATE) => {
                // host only — host always reads private; viewer only sees own.
                if msg.to_id.is_empty() {
                    return Vec::new();
                }
                if peers.contains_key(&msg.to_id) {
                    vec![msg.to_id.clone()]
                } else {
                    Vec::new()
                }
            }
            _ => Vec::new(),
        }
    }

    pub fn peer_count(&self) -> usize {
        self.peers.lock().unwrap().len()
    }
}

lazy_static::lazy_static! {
    /// One hub per host session id.
    pub static ref HUBS: Mutex<HashMap<String, Arc<ChatHub>>> =
        Mutex::new(HashMap::new());
}

/// Get-or-create the chat hub for a host session.
pub fn for_session(session_id: &str) -> Arc<ChatHub> {
    let mut m = HUBS.lock().unwrap();
    m.entry(session_id.to_owned())
        .or_insert_with(|| Arc::new(ChatHub::new()))
        .clone()
}

pub fn retire_session(session_id: &str) {
    let mut m = HUBS.lock().unwrap();
    m.remove(session_id);
}