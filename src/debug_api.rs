//! Local-only diagnostics for repeatable remote-session tests.
//!
//! The server is intentionally read-only and is enabled only for debug builds
//! with `LDESK_DEBUG_API=1`. It must never become a remotely reachable control
//! surface in a release package.

use hbb_common::log;
use once_cell::sync::Lazy;
use rand::RngCore;
use serde::Serialize;
use serde_json::json;
use std::{
    collections::HashMap,
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    sync::RwLock,
    thread,
    time::{SystemTime, UNIX_EPOCH},
};

const MAX_REQUEST_BYTES: usize = 32 * 1024;

#[derive(Clone, Debug, Serialize)]
struct Snapshot {
    peer_id: String,
    attempt: u64,
    handshake_successes: u64,
    first_frame_successes: u64,
    direct_successes: u64,
    relay_successes: u64,
    error_attempts: u64,
    disconnects: u64,
    stable_30m_completions: u64,
    first_frame_latency_total_ms: u128,
    state: String,
    secure: bool,
    direct: bool,
    stream_type: String,
    connected_at_ms: u128,
    first_frame_at_ms: Option<u128>,
    disconnected_at_ms: Option<u128>,
    last_session_duration_ms: Option<u128>,
    last_error: Option<String>,
}

static SESSIONS: Lazy<RwLock<HashMap<String, Snapshot>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

fn now_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

/// Start the diagnostics listener when explicitly requested by a debug build.
pub fn maybe_start() {
    if !cfg!(debug_assertions) || std::env::var("LDESK_DEBUG_API").as_deref() != Ok("1") {
        return;
    }

    let token = std::env::var("LDESK_DEBUG_API_TOKEN").unwrap_or_else(|_| {
        let mut bytes = [0u8; 24];
        rand::thread_rng().fill_bytes(&mut bytes);
        hex::encode(bytes)
    });
    if token.len() < 16 {
        eprintln!("LDESK_DEBUG_API_TOKEN must contain at least 16 characters");
        return;
    }

    let listener = match TcpListener::bind(("127.0.0.1", 0)) {
        Ok(listener) => listener,
        Err(error) => {
            eprintln!("LDESK_DEBUG_API failed to bind: {error}");
            return;
        }
    };
    let address = listener
        .local_addr()
        .map(|address| address.to_string())
        .unwrap_or_else(|_| "127.0.0.1:0".to_owned());
    let message = format!(
        "LDESK_DEBUG_API listening on http://{address}; token={token}; endpoints=/v1/health,/v1/sessions"
    );
    eprintln!("{message}");
    log::info!("{message}");

    thread::spawn(move || {
        for stream in listener.incoming() {
            match stream {
                Ok(stream) => {
                    let token = token.clone();
                    thread::spawn(move || serve(stream, &token));
                }
                Err(error) => log::warn!("LDESK_DEBUG_API accept failed: {error}"),
            }
        }
    });
}

pub fn record_connection(peer_id: &str, secure: bool, direct: bool, stream_type: &str) {
    if peer_id.is_empty() {
        return;
    }
    let mut sessions = SESSIONS.write().unwrap();
    let snapshot = sessions
        .entry(peer_id.to_owned())
        .or_insert_with(|| empty_snapshot(peer_id));
    snapshot.attempt = snapshot.attempt.saturating_add(1);
    snapshot.handshake_successes = snapshot.handshake_successes.saturating_add(1);
    if direct {
        snapshot.direct_successes = snapshot.direct_successes.saturating_add(1);
    } else {
        snapshot.relay_successes = snapshot.relay_successes.saturating_add(1);
    }
    snapshot.state = "connected".to_owned();
    snapshot.secure = secure;
    snapshot.direct = direct;
    snapshot.stream_type = stream_type.to_owned();
    snapshot.connected_at_ms = now_ms();
    snapshot.first_frame_at_ms = None;
    snapshot.disconnected_at_ms = None;
    snapshot.last_session_duration_ms = None;
    snapshot.last_error = None;
}

pub fn mark_first_frame(peer_id: &str) {
    let mut sessions = SESSIONS.write().unwrap();
    if let Some(snapshot) = sessions.get_mut(peer_id) {
        if snapshot.first_frame_at_ms.is_none() {
            let first_frame_at_ms = now_ms();
            snapshot.first_frame_at_ms = Some(first_frame_at_ms);
            snapshot.first_frame_successes = snapshot.first_frame_successes.saturating_add(1);
            snapshot.first_frame_latency_total_ms = snapshot
                .first_frame_latency_total_ms
                .saturating_add(first_frame_at_ms.saturating_sub(snapshot.connected_at_ms));
        }
        return;
    }
    // Direct IP sessions may report the peer's stable ID after the connection
    // was keyed by its IP:port. If there is only one active session, it is
    // unambiguous and can still be credited with the first frame.
    let active = sessions
        .values_mut()
        .filter(|snapshot| snapshot.state == "connected")
        .collect::<Vec<_>>();
    if active.len() == 1 && active[0].first_frame_at_ms.is_none() {
        let first_frame_at_ms = now_ms();
        active[0].first_frame_at_ms = Some(first_frame_at_ms);
        active[0].first_frame_successes = active[0].first_frame_successes.saturating_add(1);
        active[0].first_frame_latency_total_ms = active[0]
            .first_frame_latency_total_ms
            .saturating_add(first_frame_at_ms.saturating_sub(active[0].connected_at_ms));
    }
}

pub fn mark_error(peer_id: &str, error: &str) {
    let mut sessions = SESSIONS.write().unwrap();
    if let Some(snapshot) = sessions.get_mut(peer_id) {
        if snapshot.state != "connected" {
            snapshot.attempt = snapshot.attempt.saturating_add(1);
            snapshot.error_attempts = snapshot.error_attempts.saturating_add(1);
            snapshot.connected_at_ms = now_ms();
            snapshot.first_frame_at_ms = None;
            snapshot.disconnected_at_ms = None;
        }
        snapshot.state = "error".to_owned();
        snapshot.last_error = Some(error.to_owned());
    } else {
        let mut snapshot = empty_snapshot(peer_id);
        snapshot.attempt = 1;
        snapshot.error_attempts = 1;
        snapshot.state = "error".to_owned();
        snapshot.connected_at_ms = now_ms();
        snapshot.last_error = Some(error.to_owned());
        sessions.insert(peer_id.to_owned(), snapshot);
    }
}

fn empty_snapshot(peer_id: &str) -> Snapshot {
    Snapshot {
        peer_id: peer_id.to_owned(),
        attempt: 0,
        handshake_successes: 0,
        first_frame_successes: 0,
        direct_successes: 0,
        relay_successes: 0,
        error_attempts: 0,
        disconnects: 0,
        stable_30m_completions: 0,
        first_frame_latency_total_ms: 0,
        state: "idle".to_owned(),
        secure: false,
        direct: false,
        stream_type: String::new(),
        connected_at_ms: 0,
        first_frame_at_ms: None,
        disconnected_at_ms: None,
        last_session_duration_ms: None,
        last_error: None,
    }
}

pub fn mark_disconnected(peer_id: &str) {
    if let Some(snapshot) = SESSIONS.write().unwrap().get_mut(peer_id) {
        let disconnected_at_ms = now_ms();
        if snapshot.state == "connected" {
            let duration_ms = disconnected_at_ms.saturating_sub(snapshot.connected_at_ms);
            snapshot.disconnects = snapshot.disconnects.saturating_add(1);
            snapshot.last_session_duration_ms = Some(duration_ms);
            if duration_ms >= 30 * 60 * 1000 {
                snapshot.stable_30m_completions = snapshot.stable_30m_completions.saturating_add(1);
            }
        }
        snapshot.state = "disconnected".to_owned();
        snapshot.disconnected_at_ms = Some(disconnected_at_ms);
    }
}

fn serve(mut stream: TcpStream, token: &str) {
    let mut request = vec![0u8; MAX_REQUEST_BYTES];
    let size = match stream.read(&mut request) {
        Ok(size) => size,
        Err(_) => return,
    };
    let request = String::from_utf8_lossy(&request[..size]);
    let mut lines = request.split("\r\n");
    let Some(request_line) = lines.next() else {
        return;
    };
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or_default();
    let path = parts.next().unwrap_or_default();
    let authorized = lines
        .take_while(|line| !line.is_empty())
        .filter_map(|line| line.split_once(':'))
        .find_map(|(name, value)| {
            if name.eq_ignore_ascii_case("authorization") {
                value.trim().strip_prefix("Bearer ")
            } else {
                None
            }
        })
        .is_some_and(|value| value.trim() == token);

    if !authorized {
        respond(&mut stream, 401, json!({"error": "unauthorized"}));
        return;
    }
    if method != "GET" {
        respond(&mut stream, 405, json!({"error": "method_not_allowed"}));
        return;
    }

    match path {
        "/v1/health" => respond(
            &mut stream,
            200,
            json!({"ok": true, "api": "debug", "pid": std::process::id(), "now_ms": now_ms()}),
        ),
        "/v1/sessions" => {
            let sessions = SESSIONS
                .read()
                .unwrap()
                .values()
                .cloned()
                .collect::<Vec<_>>();
            respond(&mut stream, 200, json!({"sessions": sessions}));
        }
        _ => respond(&mut stream, 404, json!({"error": "not_found"})),
    }
}

fn respond(stream: &mut TcpStream, status: u16, body: serde_json::Value) {
    let body = body.to_string();
    let reason = match status {
        200 => "OK",
        401 => "Unauthorized",
        404 => "Not Found",
        405 => "Method Not Allowed",
        _ => "Error",
    };
    let response = format!(
        "HTTP/1.1 {status} {reason}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let _ = stream.write_all(response.as_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::Shutdown;

    #[test]
    fn snapshot_records_connection_and_first_frame_once() {
        let peer_id = "debug-api-test-peer";
        record_connection(peer_id, true, true, "TCP");
        mark_first_frame(peer_id);
        let first = SESSIONS.read().unwrap().get(peer_id).unwrap().clone();
        mark_first_frame(peer_id);
        let second = SESSIONS.read().unwrap().get(peer_id).unwrap().clone();
        assert_eq!(first.first_frame_at_ms, second.first_frame_at_ms);
        assert_eq!(first.attempt, 1);
        assert_eq!(first.handshake_successes, 1);
        assert_eq!(first.first_frame_successes, 1);
        assert_eq!(first.direct_successes, 1);
        assert_eq!(first.disconnects, 0);
        assert_eq!(first.stream_type, "TCP");
        mark_disconnected(peer_id);
        assert_eq!(
            SESSIONS.read().unwrap().get(peer_id).unwrap().state,
            "disconnected"
        );
        SESSIONS.write().unwrap().remove(peer_id);
    }

    fn request_once(request: &str, token: &str) -> String {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let address = listener.local_addr().unwrap();
        let token = token.to_owned();
        let server = thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            serve(stream, &token);
        });
        let mut client = TcpStream::connect(address).unwrap();
        client.write_all(request.as_bytes()).unwrap();
        client.shutdown(Shutdown::Write).unwrap();
        let mut response = String::new();
        client.read_to_string(&mut response).unwrap();
        server.join().unwrap();
        response
    }

    #[test]
    fn health_endpoint_requires_bearer_token() {
        let unauthorized = request_once("GET /v1/health HTTP/1.1\r\n\r\n", "test-token");
        assert!(unauthorized.starts_with("HTTP/1.1 401"));

        let authorized = request_once(
            "GET /v1/health HTTP/1.1\r\nauthorization: Bearer test-token\r\n\r\n",
            "test-token",
        );
        assert!(authorized.starts_with("HTTP/1.1 200"));
        assert!(authorized.contains("\"api\":\"debug\""));
    }
}
