//! LUODA 3.1: Per-connection viewer-mode state.
//!
//! A [`crate::server::Connection`] carries an `Option<ViewerState>` field.
//! When it is `Some`, the connection behaves as a view-only audience member
//! of the host's session (no keyboard / mouse / clipboard / file channel);
//! the host retains its own authorized controlling connection in parallel.
//!
//! This is intentionally tiny: most of the viewer bookkeeping (badge updates,
//! list synchronization, raise-hand timestamps) lives in `viewer_registry`.
//! Only the per-connection data that must survive a frame-level query without
//! touching the registry mutex lives here.

use std::time::Instant;

/// A viewer admitted to a host session in view-only mode.
///
/// Fields are `pub(crate)` so the registry / broadcast modules can read them
/// without forcing every access through an accessor method.
#[derive(Clone, Debug)]
pub struct ViewerState {
    /// Stable, host-unique identifier for this viewer (UUID v4 string).
    pub viewer_id: String,
    /// Human-readable name shown in the viewer list. May be empty.
    pub display_name: String,
    /// True iff the viewer has currently raised their hand to speak.
    pub raise_hand: bool,
    /// When the current raise-hand started, so the host can show a timer.
    /// `None` when `raise_hand` is `false`.
    pub raise_hand_at: Option<Instant>,
    /// True iff the controlling peer has promoted this viewer to co-host.
    /// 3.1 only flips the badge; the data path stays view-only.
    pub promoted: bool,
}

impl ViewerState {
    pub fn new(viewer_id: String, display_name: String) -> Self {
        Self {
            viewer_id,
            display_name,
            raise_hand: false,
            raise_hand_at: None,
            promoted: false,
        }
    }
}