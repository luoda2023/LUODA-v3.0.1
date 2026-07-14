//! LUODA 3.1.1 — Viewer Direct Channel
//! -------------------------------------------------------------------------
//! Viewers receive host video / audio / chat over a *direct* P2P channel.
//! The rendezvous server is *never* used as a media relay. The host either
//! accepts the viewer dial-in ( HolePunch result ) or the viewer punches
//! directly to the host's public / LAN endpoint extracted from the
//! rendezvous-mediated control message.
//!
//! This module deliberately does *not* introduce a separate encoder path:
//! it re-uses the host's existing connection-level video frame bus and
//! clones encoded frames to each viewer subscriber. CPU cost is just the
//! per-viewer copy + crypto (the heavy work — capture / encode — is paid
//! exactly once by the existing connection, regardless of viewer count).
//!
//! Uplink budget: the host UI watches [`UplinkMeter`] and rejects new
//! viewers when the cap is reached. This is enforced by `viewer_registry`.

use std::{
    sync::{Arc, Mutex},
    time::Instant,
};

use hbb_common::{
    message::{ChatBroadcast, Message, VideoFrame, ViewerBadgeUpdate, ViewerInfo, ViewerListUpdate},
    rendezvous::RendezvousMessage,
};
use tokio::sync::broadcast;

/// Channel capacity per host session. Larger = smoother playback under
/// transient congestion, at the cost of host RAM.
const FRAME_CHANNEL_CAPACITY: usize = 64;

/// Frame emitted on the host-side fan-out bus. We use `Vec<u8>` (encoded
/// protobuf Message bytes) so subscribers just forward without re-encoding.
pub type FrameBytes = Vec<u8>;

pub struct DirectChannel {
    /// Fan-out sender. Clone per subscriber.
    tx: broadcast::Sender<FrameBytes>,
    /// Uplink meter — bytes/sec actually pushed to viewers (not the encoded
    /// size; this is what leaves the NIC).
    meter: Arc<Mutex<UplinkMeter>>,
}

#[derive(Default, Clone)]
pub struct UplinkMeter {
    pub total_bps: u64,
    pub last_sample_at: Option<Instant>,
    pub last_sample_bytes: u64,
}

impl DirectChannel {
    pub fn new() -> Self {
        let (tx, _) = broadcast::channel(FRAME_CHANNEL_CAPACITY);
        Self { tx, meter: Arc::new(Mutex::new(UplinkMeter::default())) }
    }

    /// Push an encoded `Message` (typically a `VideoFrame`-bearing message)
    /// to all current viewer subscribers. Stale subscribers (lagging behind
    /// `FRAME_CHANNEL_CAPACITY`) are silently dropped — they can re-join.
    pub fn publish(&self, frame: FrameBytes) {
        let now = Instant::now();
        {
            let mut m = self.meter.lock().unwrap();
            m.last_sample_bytes = m.last_sample_bytes.saturating_add(frame.len() as u64);
            if let Some(t) = m.last_sample_at {
                let elapsed = now.duration_since(t).as_secs_f64().max(0.001);
                if elapsed >= 1.0 {
                    m.total_bps = ((m.last_sample_bytes as f64 * 8.0) / elapsed) as u64;
                    m.last_sample_bytes = 0;
                    m.last_sample_at = Some(now);
                }
            } else {
                m.last_sample_at = Some(now);
            }
        }
        let _ = self.tx.send(frame);
    }

    /// Subscribe a viewer. Returns a receiver that yields encoded protobuf
    /// `Message` bytes. The host transport should forward each received
    /// frame to the viewer's P2P socket (TCP / QUIC / UDP — caller's choice).
    pub fn subscribe(&self) -> broadcast::Receiver<FrameBytes> {
        self.tx.subscribe()
    }

    /// Current uplink used by viewer streams, in bits/sec.
    pub fn uplink_bps(&self) -> u64 {
        self.meter.lock().unwrap().total_bps
    }
}

/// Convert a host-side `Message` (e.g. `video_frame`) to wire bytes for
/// the viewer fan-out bus.
pub fn encode_message(msg: &Message) -> FrameBytes {
    use hbb_common::protobuf::Message as _;
    msg.write_to_bytes().unwrap_or_default()
}

lazy_static::lazy_static! {
    pub static ref HOST_CHANNELS:
        std::sync::Mutex<std::collections::HashMap<String, Arc<DirectChannel>>> =
        std::sync::Mutex::new(std::collections::HashMap::new());
}

/// Get-or-create the `DirectChannel` for a host session id.
pub fn for_session(session_id: &str) -> Arc<DirectChannel> {
    let mut m = HOST_CHANNELS.lock().unwrap();
    m.entry(session_id.to_owned())
        .or_insert_with(|| Arc::new(DirectChannel::new()))
        .clone()
}

/// Drop the channel — called when the host session ends.
pub fn retire_session(session_id: &str) {
    let mut m = HOST_CHANNELS.lock().unwrap();
    m.remove(session_id);
}