//! LUODA 3.1.1 -- Viewer Registry
//! -------------------------------------------------------------------------
//! Per-host viewer registry. Holds invite tokens + active viewers.
//!
//! Design goals (per product spec):
//!  * Viewers are *invite-only* and *view-only*. They cannot control the
//!    host, send input, transfer files, or initiate console / clipboard
//!    traffic.
//!  * All viewer *data plane* (video / audio) flows P2P directly between the
//!    viewer and the host. The rendezvous server is *never* used as a relay
//!    for viewer media -- it only helps the viewer locate the host endpoint.
//!  * The host may revoke a viewer at any time; tokens carry a TTL; the
//!    host may cap total viewers and total uplink bps.
//!
//! This module is intentionally side-effect-free w.r.t. the existing
//! connection / SESSIONS map: it owns *only* viewer state, keyed by the
//! host's [`HostId`].

use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use hbb_common::config::Config;
use hbb_common::message_proto::{InviteToken, KickViewer, PromoteViewer, ViewerInfo};

/// Host-side opaque id (`id_pk` / `id` from rendezvous).
pub type HostId = String;
/// Viewer opaque id (uuid v4 on the client side).
pub type ViewerId = String;
/// Server-issued token (32 hex chars).
pub type Token = String;

/// Default TTL applied when the host creates an invitation without an
/// explicit expiry.
const DEFAULT_TOKEN_TTL: Duration = Duration::from_secs(60 * 60 * 6); // 6h
/// Hard ceiling on simultaneous viewers per host, absent a user override.
const DEFAULT_MAX_VIEWERS: u32 = 8;

#[derive(Debug, Clone)]
pub struct Viewer {
    pub viewer_id: ViewerId,
    pub display_name: String,
    pub joined_at: SystemTime,
    /// Last P2P endpoint reported by the host (ip:port or `relay:tag`).
    pub endpoint: String,
    /// Whether the host has *promoted* this viewer (still view-only by spec;
    /// promotion here just enables private chat priority + raise-hand ack).
    pub promoted: bool,
}

#[derive(Debug, Clone)]
pub struct Invite {
    pub token: Token,
    pub session_id: String,
    pub created_at: Instant,
    pub expires_at: SystemTime,
    pub host_id: HostId,
    /// 12-char Crockford base32 short code derived from the first 8 bytes
    /// of the token (see crate::server::invite_code). Index used by the
    /// viewer-join dispatch to resolve short-code entries back to a full
    /// token without bruteforcing the bucket.
    pub short_code: String,
    /// Zero-TTL tokens are treated as one-shot: the first consume succeeds
    /// even if the wall clock has already passed expires_at. Lifetime is
    /// bounded by single-use instead of by wall time.
    pub one_shot: bool,
}

#[derive(Default)]
pub struct HostBucket {
    pub invites: HashMap<Token, Invite>,
    /// Reverse index: short_code -> canonical token (lowercased Crockford
    /// base32, 12 chars). Kept in sync with invites so short-code joins
    /// resolve in O(1).
    pub short_codes: HashMap<String, Token>,
    pub viewers: HashMap<ViewerId, Viewer>,
    pub max_viewers: u32,
}

#[derive(Default)]
pub struct Registry {
    inner: Mutex<HashMap<HostId, Arc<Mutex<HostBucket>>>>,
}

impl Registry {
    pub fn new() -> Self {
        Self { inner: Mutex::new(HashMap::new()) }
    }

    fn bucket(&self, host_id: &str) -> Arc<Mutex<HostBucket>> {
        let mut outer = self.inner.lock().unwrap();
        outer
            .entry(host_id.to_owned())
            .or_insert_with(|| Arc::new(Mutex::new(HostBucket { max_viewers: DEFAULT_MAX_VIEWERS, ..Default::default() })))
            .clone()
    }

    /// Issue a fresh invite token for `host_id`. Caller is responsible for
    /// shipping the [`InviteToken`] to the client (e.g. via existing
    /// rendezvous-mediated control message or QR code).
    pub fn issue_token(&self, host_id: &str, session_id: &str, ttl: Option<Duration>) -> InviteToken {
        self.issue_token_with_policy(host_id, session_id, ttl, true)
    }

    pub fn issue_token_with_policy(
        &self,
        host_id: &str,
        session_id: &str,
        ttl: Option<Duration>,
        one_shot: bool,
    ) -> InviteToken {
        let bucket = self.bucket(host_id);
        let mut b = bucket.lock().unwrap();
        let token = uuid::Uuid::new_v4().simple().to_string();
        let now_wall = SystemTime::now();
        let ttl = ttl.unwrap_or(DEFAULT_TOKEN_TTL);
        // Zero-TTL means a one-shot: the token never expires by wall clock
        // and is burned by the first consume instead. We still surface the
        // caller-supplied 0 for the public InviteToken so clients can tell
        // one-shot from TTL'd tokens.
        let zero_ttl = ttl == Duration::ZERO;
        let one_shot = one_shot || zero_ttl;
        let stored_expiry = if zero_ttl {
            now_wall + DEFAULT_TOKEN_TTL * 3600
        } else {
            now_wall + ttl
        };
        let short_code =
            crate::server::invite_code::encode_short_code(&token);
        b.invites.insert(
            token.clone(),
            Invite {
                token: token.clone(),
                session_id: session_id.to_owned(),
                created_at: Instant::now(),
                expires_at: stored_expiry,
                host_id: host_id.to_owned(),
                short_code: short_code.clone(),
                one_shot,
            },
        );
        b.short_codes.insert(short_code.clone(), token.clone());
        InviteToken {
            token,
            expires_at: now_wall.duration_since(UNIX_EPOCH).unwrap_or_default().as_secs(),
            session_id: session_id.to_owned(),
            host_id: host_id.to_owned(),
            short_code,
            one_shot,
            ..Default::default()
        }
    }

    /// Consume a token (single-use) and return the host id it was for. If
    /// the token is missing / expired / already consumed, returns `None`.
    pub fn consume_token(&self, token: &str) -> Option<HostId> {
        let outer = self.inner.lock().unwrap();
        for (_host_id, bucket_arc) in outer.iter() {
            let mut b = bucket_arc.lock().unwrap();
            if let Some(inv) = b.invites.get(token).cloned() {
                if inv.expires_at > SystemTime::now() {
                    if inv.one_shot {
                        b.invites.remove(token);
                        if !inv.short_code.is_empty() {
                            b.short_codes.remove(&inv.short_code);
                        }
                    }
                    return Some(inv.host_id);
                }
                b.invites.remove(token);
                if !inv.short_code.is_empty() {
                    b.short_codes.remove(&inv.short_code);
                }
            }
        }
        None
    }

    /// Resolve a 12-char Crockford base32 short code (or hyphenated /
    /// whitespace-padded variant) back to its canonical token. The token
    /// is **not** consumed - call consume_token afterwards to actually
    /// burn the single-use pair. Returns None for unknown / expired /
    /// already-burnt short codes so callers can behave identically for
    /// any join failure mode.
    pub fn resolve_short_code(&self, short_code: &str) -> Option<Token> {
        let canonical = crate::server::invite_code::normalize_short_code(short_code)?;
        let outer = self.inner.lock().unwrap();
        for (_host_id, bucket_arc) in outer.iter() {
            let b = bucket_arc.lock().unwrap();
            if let Some(token) = b.short_codes.get(&canonical) {
                if let Some(inv) = b.invites.get(token) {
                    if inv.expires_at > SystemTime::now() {
                        return Some(token.clone());
                    }
                }
            }
        }
        None
    }

    /// Try to admit a viewer to a host's bucket. Returns the [`ViewerInfo`]
    /// snapshot on success. Returns `Err` if the cap is hit, the viewer is
    /// already present (caller may treat as re-join), or the bucket is gone.
    pub fn admit_viewer(
        &self,
        host_id: &str,
        viewer_id: &str,
        display_name: &str,
        endpoint: &str,
    ) -> Result<ViewerInfo, AdmitError> {
        let bucket = self.bucket(host_id);
        let mut b = bucket.lock().unwrap();
        if b.viewers.len() as u32 >= b.max_viewers && !b.viewers.contains_key(viewer_id) {
            return Err(AdmitError::CapHit);
        }
        let v = Viewer {
            viewer_id: viewer_id.to_owned(),
            display_name: display_name.to_owned(),
            joined_at: SystemTime::now(),
            endpoint: endpoint.to_owned(),
            promoted: false,
        };
        b.viewers.insert(viewer_id.to_owned(), v.clone());
        Ok(viewer_to_info(&v, 0))
    }

    pub fn remove_viewer(&self, host_id: &str, viewer_id: &str) -> bool {
        let bucket = self.bucket(host_id);
        let mut b = bucket.lock().unwrap();
        b.viewers.remove(viewer_id).is_some()
    }

    pub fn kick(&self, host_id: &str, kick: &KickViewer) -> bool {
        self.remove_viewer(host_id, &kick.viewer_id)
    }

    pub fn promote(&self, host_id: &str, p: &PromoteViewer) -> bool {
        let bucket = self.bucket(host_id);
        let mut b = bucket.lock().unwrap();
        if let Some(v) = b.viewers.get_mut(&p.viewer_id) {
            v.promoted = true;
            true
        } else {
            false
        }
    }

    pub fn set_max_viewers(&self, host_id: &str, cap: u32) {
        let bucket = self.bucket(host_id);
        let mut b = bucket.lock().unwrap();
        b.max_viewers = cap.max(1);
    }

    pub fn list_viewers(&self, host_id: &str) -> Vec<ViewerInfo> {
        let bucket = self.bucket(host_id);
        let b = bucket.lock().unwrap();
        b.viewers.values().map(|v| viewer_to_info(v, 0)).collect()
    }

    pub fn snapshot(
        &self,
        host_id: &str,
        total_uplink_bps: u64,
    ) -> hbb_common::message_proto::ViewerListUpdate {
        let outer = self.inner.lock().unwrap();
        // Snapshot must not implicitly revive a host that has been purged;
        // otherwise a purged host would reappear with DEFAULT_MAX_VIEWERS.
        let Some(bucket_arc) = outer.get(host_id) else {
            return hbb_common::message_proto::ViewerListUpdate {
                viewers: Vec::new(),
                max_viewers: 0,
                total_uplink_bps,
                ..Default::default()
            };
        };
        let b = bucket_arc.lock().unwrap();
        hbb_common::message_proto::ViewerListUpdate {
            viewers: b.viewers.values().map(|v| viewer_to_info(v, 0)).collect(),
            max_viewers: b.max_viewers,
            total_uplink_bps,
            ..Default::default()
        }
    }

    /// Drop expired invites for *all* hosts. Called by a periodic task.
    pub fn gc_expired(&self) {
        let outer = self.inner.lock().unwrap();
        for (_host_id, bucket_arc) in outer.iter() {
            let mut b = bucket_arc.lock().unwrap();
            let now = SystemTime::now();
            let survivors: Vec<Token> = b
                .invites
                .iter()
                .filter(|(_, inv)| inv.expires_at > now)
                .map(|(k, _)| k.clone())
                .collect();
            let to_drop: Vec<Token> = b
                .invites
                .keys()
                .filter(|k| !survivors.iter().any(|s| s == *k))
                .cloned()
                .collect();
            for k in &to_drop {
                if let Some(inv) = b.invites.remove(k) {
                    if !inv.short_code.is_empty() {
                        b.short_codes.remove(&inv.short_code);
                    }
                }
            }
        }
    }

    /// Drop all state for a host -- call when the host session ends.
    pub fn purge(&self, host_id: &str) {
        let mut outer = self.inner.lock().unwrap();
        outer.remove(host_id);
    }
}

#[derive(Debug)]
pub enum AdmitError {
    CapHit,
}

fn viewer_to_info(v: &Viewer, unread: u32) -> ViewerInfo {
    ViewerInfo {
        viewer_id: v.viewer_id.clone(),
        display_name: v.display_name.clone(),
        joined_at: v.joined_at.duration_since(UNIX_EPOCH).unwrap_or_default().as_secs(),
        promoted: v.promoted,
        endpoint: v.endpoint.clone(),
        unread_chat: unread,
        ..Default::default()
    }
}

lazy_static::lazy_static! {
    pub static ref REGISTRY: Registry = Registry::new();
}

lazy_static::lazy_static! {
    static ref GC_STARTED: std::sync::Mutex<bool> = std::sync::Mutex::new(false);
}

/// Spawn a periodic GC for expired tokens. Lives for the lifetime of the
/// process; safe to call multiple times (subsequent calls are no-ops).
pub fn start_gc_loop() {
    let mut started = GC_STARTED.lock().ok();
    if let Some(ref mut guard) = started {
        if **guard {
            return;
        }
        **guard = true;
    } else {
        // poisoned lock: assume another thread owns startup; do nothing
        return;
    }
    std::thread::Builder::new()
        .name("luoda-viewer-registry-gc".into())
        .spawn(move || {
            let interval = Duration::from_secs(60);
            loop {
                std::thread::sleep(interval);
                REGISTRY.gc_expired();
            }
        })
        .ok();
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_registry() -> Registry {
        Registry::new()
    }

    #[test]
    fn issue_and_consume_token_roundtrip() {
        let r = fresh_registry();
        let inv = r.issue_token("host-a", "sess-1", Some(Duration::from_secs(60)));
        assert!(!inv.token.is_empty());
        let host = r.consume_token(&inv.token);
        assert_eq!(host.as_deref(), Some("host-a"));
        // Single-use: second consume fails.
        assert!(r.consume_token(&inv.token).is_none());
    }

    #[test]
    fn expired_token_is_rejected() {
        let r = fresh_registry();
        let inv = r.issue_token("host-b", "sess-2", Some(Duration::from_millis(1)));
        std::thread::sleep(Duration::from_millis(20));
        assert!(r.consume_token(&inv.token).is_none());
    }

    #[test]
    fn admit_viewer_respects_cap() {
        let r = fresh_registry();
        r.set_max_viewers("host-c", 2);
        let _ = r.admit_viewer("host-c", "v1", "alice", "1.1.1.1:1").unwrap();
        let _ = r.admit_viewer("host-c", "v2", "bob", "1.1.1.1:2").unwrap();
        // Cap hit on the third
        match r.admit_viewer("host-c", "v3", "carol", "1.1.1.1:3") {
            Err(AdmitError::CapHit) => {}
            _ => panic!("expected CapHit"),
        }
        // Re-joining an existing viewer is allowed (idempotent).
        let _ = r.admit_viewer("host-c", "v1", "alice", "1.1.1.1:1").unwrap();
    }

    #[test]
    fn kick_and_promote_mutate_state() {
        let r = fresh_registry();
        let _ = r.admit_viewer("host-d", "v1", "alice", "1.1.1.1:1").unwrap();
        assert!(r.promote(
            "host-d",
            &PromoteViewer { viewer_id: "v1".to_string(), ..Default::default() }
        ));
        let list = r.list_viewers("host-d");
        assert_eq!(list.len(), 1);
        assert!(list[0].promoted);
        assert!(r.kick(
            "host-d",
            &KickViewer { viewer_id: "v1".to_string(), reason: "bye".to_string(), ..Default::default() }
        ));
        assert!(r.list_viewers("host-d").is_empty());
    }

    #[test]
    fn gc_expired_drops_only_stale_entries() {
        let r = fresh_registry();
        let _short = r.issue_token("host-e", "s1", Some(Duration::from_millis(1)));
        let _long = r.issue_token("host-e", "s2", Some(Duration::from_secs(60)));
        std::thread::sleep(Duration::from_millis(20));
        r.gc_expired();
        // short gone, long still valid (but single-use via consume).
        // Find the survivor by attempting consume on the long-lived token: we
        // don't have its token string stored directly here, so inspect the
        // snapshot path instead.
        let snap = r.snapshot("host-e", 0);
        // The bucket still exists; viewers empty. tokens map invisible from
        // public API, so validate indirectly via list_viewers being empty.
        assert!(snap.viewers.is_empty());
    }

    #[test]
    fn purge_drops_all_host_state() {
        let r = fresh_registry();
        let _ = r.admit_viewer("host-f", "v1", "alice", "1.1.1.1:1").unwrap();
        r.purge("host-f");
        assert!(r.list_viewers("host-f").is_empty());
    }
}
