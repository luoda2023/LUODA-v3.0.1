//! Local-only diagnostics for repeatable remote-session tests.
//!
//! The server is disabled by default. It starts only when `LDESK_DEBUG_API=1`,
//! binds to loopback, and requires a bearer token for its test-only actions.

use hbb_common::log;
use once_cell::sync::Lazy;
use rand::RngCore;
use serde::Serialize;
use serde_json::json;
use std::{
    collections::HashMap,
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    sync::{Once, RwLock},
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
static CHAT_MESSAGES: Lazy<RwLock<Vec<String>>> = Lazy::new(|| RwLock::new(Vec::new()));
static PERMISSIONS: Lazy<RwLock<HashMap<String, HashMap<String, bool>>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));
static INPUT_EVENTS: Lazy<RwLock<Vec<String>>> = Lazy::new(|| RwLock::new(Vec::new()));
static START: Once = Once::new();

fn now_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

/// Start the diagnostics listener when explicitly requested.
pub fn maybe_start() {
    if std::env::var("LDESK_DEBUG_API").as_deref() != Ok("1") {
        return;
    }

    START.call_once(start);
}

fn start() {
    let token = std::env::var("LDESK_DEBUG_API_TOKEN").unwrap_or_else(|_| {
        let mut bytes = [0u8; 24];
        rand::thread_rng().fill_bytes(&mut bytes);
        hex::encode(bytes)
    });
    if token.len() < 16 {
        use std::io::Write as _; let _ = std::io::stderr().write_all(b"LDESK_DEBUG_API_TOKEN must contain at least 16 characters\n");
        return;
    }

    let listener = match TcpListener::bind(("127.0.0.1", 38881)).or_else(|_| TcpListener::bind(("127.0.0.1", 0))) {
        Ok(listener) => listener,
        Err(error) => {
            use std::io::Write as _; let _ = writeln!(std::io::stderr(), "LDESK_DEBUG_API failed to bind: {error}");
            return;
        }
    };
    let address = listener
        .local_addr()
        .map(|address| address.to_string())
        .unwrap_or_else(|_| "127.0.0.1:0".to_owned());
    let message = format!(
        "LDESK_DEBUG_API listening on http://{address}; token={token}; endpoints=/v1/health,/v1/sessions,/v1/connect-chat,/v1/chat,/v1/chat-messages"
    );
    use std::io::Write as _; let _ = writeln!(std::io::stderr(), "{message}");
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
    let mut active = sessions
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

/// Record a short chat-pipeline event (debug only). Long envelopes go
/// through [record_chat_message]; this is for routing diagnostics.
pub fn record_chat_event(tag: &str, detail: &str) {
    if std::env::var("LDESK_DEBUG_API").as_deref() != Ok("1") {
        return;
    }
    let mut messages = CHAT_MESSAGES.write().unwrap();
    if messages.len() >= 200 {
        messages.remove(0);
    }
    messages.push(format!("{tag}: {detail}"));
}

pub fn record_chat_message(message: &str) {
    if std::env::var("LDESK_DEBUG_API").as_deref() != Ok("1") {
        return;
    }
    let mut messages = CHAT_MESSAGES.write().unwrap();
    if messages.len() >= 100 {
        messages.remove(0);
    }
    messages.push(message.to_owned());
}

/// Record a permission update received from the peer (debug only).
pub fn record_permission(peer_id: &str, name: &str, value: bool) {
    if std::env::var("LDESK_DEBUG_API").as_deref() != Ok("1") || peer_id.is_empty() {
        return;
    }
    PERMISSIONS
        .write()
        .unwrap()
        .entry(peer_id.to_owned())
        .or_default()
        .insert(name.to_owned(), value);
}

/// Record an input message Flutter asked to forward to the peer (debug only).
pub fn record_input(peer_id: &str, detail: &str) {
    if std::env::var("LDESK_DEBUG_API").as_deref() != Ok("1") || peer_id.is_empty() {
        return;
    }
    let mut events = INPUT_EVENTS.write().unwrap();
    if events.len() >= 300 {
        events.remove(0);
    }
    events.push(format!("{peer_id} {detail}"));
}

fn read_http_request(stream: &mut TcpStream) -> Option<Vec<u8>> {
    let mut request = Vec::new();
    let mut chunk = [0u8; 4096];
    let mut header_end = None;
    let mut content_length = 0usize;
    loop {
        let size = stream.read(&mut chunk).ok()?;
        if size == 0 {
            return header_end.map(|_| request);
        }
        if request.len().saturating_add(size) > MAX_REQUEST_BYTES {
            return None;
        }
        request.extend_from_slice(&chunk[..size]);
        if header_end.is_none() {
            if let Some(position) = request
                .windows(4)
                .position(|window| window == b"\r\n\r\n")
            {
                let end = position + 4;
                let headers = String::from_utf8_lossy(&request[..position]);
                content_length = headers
                    .lines()
                    .find_map(|line| {
                        let (name, value) = line.split_once(':')?;
                        name.eq_ignore_ascii_case("content-length")
                            .then(|| value.trim().parse::<usize>().ok())
                            .flatten()
                    })
                    .unwrap_or_default();
                if content_length > MAX_REQUEST_BYTES.saturating_sub(end) {
                    return None;
                }
                header_end = Some(end);
            }
        }
        if let Some(end) = header_end {
            let total = end.saturating_add(content_length);
            if request.len() >= total {
                request.truncate(total);
                return Some(request);
            }
        }
    }
}

fn serve(mut stream: TcpStream, token: &str) {
    let Some(request_bytes) = read_http_request(&mut stream) else {
        return;
    };
    let request = String::from_utf8_lossy(&request_bytes);
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
    if method == "POST" && path == "/v1/connect-chat" {
        let body = request
            .split_once("\r\n\r\n")
            .map(|(_, body)| body)
            .unwrap_or_default();
        let payload = match serde_json::from_str::<serde_json::Value>(body) {
            Ok(payload) => payload,
            Err(_) => {
                respond(&mut stream, 400, json!({"error": "invalid_json"}));
                return;
            }
        };
        let peer_id = payload
            .get("peer_id")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .trim();
        let target = payload
            .get("target")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .trim();
        if peer_id.is_empty() || target.is_empty() || target.len() > 1024 {
            respond(&mut stream, 400, json!({"error": "invalid_chat_target"}));
            return;
        }
 use hbb_common::rendezvous_proto::ConnType;
 if let Some(session) =
 crate::flutter::sessions::get_session_by_peer_id(peer_id.to_owned(), ConnType::CHAT)
 {
 let connected = session.connection_round_state.lock().unwrap().is_connected();
 if connected {
 respond(
 &mut stream,
 200,
 json!({"ok": true, "peer_id": peer_id, "connected": true}),
 );
 return;
 }
 // Session exists but is disconnected — remove it so we can create a fresh one.
 let _ = crate::flutter::sessions::remove_session_by_peer_id(peer_id.to_owned(), ConnType::CHAT);
 }
        let session_id = uuid::Uuid::new_v4();
        let session = match crate::flutter::session_add(
            &session_id,
            target,
            false,
            false,
            false,
            false,
            false,
            true,
            "",
            false,
            String::new(),
            false,
            None,
        ) {
            Ok(session) => session,
            Err(error) => {
                respond(
                    &mut stream,
                    409,
                    json!({"error": "chat_session_failed", "detail": error.to_string()}),
                );
                return;
            }
        };
        let round = session.connection_round_state.lock().unwrap().new_round();
        std::thread::spawn(move || crate::ui_session_interface::io_loop((*session).clone(), round));
        respond(
            &mut stream,
            200,
            json!({"ok": true, "peer_id": peer_id, "connected": false}),
        );
        return;
    }
    if method == "POST" && path == "/v1/chat" {
        let body = request
            .split_once("\r\n\r\n")
            .map(|(_, body)| body)
            .unwrap_or_default();
        let payload = match serde_json::from_str::<serde_json::Value>(body) {
            Ok(payload) => payload,
            Err(_) => {
                respond(&mut stream, 400, json!({"error": "invalid_json"}));
                return;
            }
        };
        let peer_id = payload
            .get("peer_id")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .trim();
        let text = payload
            .get("text")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default();
        if peer_id.is_empty() || text.trim().is_empty() || text.len() > 4096 {
            respond(&mut stream, 400, json!({"error": "invalid_chat"}));
            return;
        }
        use hbb_common::rendezvous_proto::ConnType;
        let session = crate::flutter::sessions::get_session_by_peer_id(
            peer_id.to_owned(),
            ConnType::CHAT,
        )
        .or_else(|| {
            crate::flutter::sessions::get_session_by_peer_id(
                peer_id.to_owned(),
                ConnType::DEFAULT_CONN,
            )
        });
        let Some(session) = session else {
            respond(
                &mut stream,
                404,
                json!({"error": "session_not_found"}),
            );
            return;
        };
        if !session.connection_round_state.lock().unwrap().is_connected() {
            respond(
                &mut stream,
                409,
                json!({"error": "session_not_connected"}),
            );
            return;
        }
        session.send_chat(text.to_owned());
        respond(&mut stream, 200, json!({"ok": true, "peer_id": peer_id}));
        return;
    }
 if method == "POST" && path == "/v1/inject-chat" {
 // Simulate receiving a chat message from a remote peer.
 // This pushes the message straight to the in-process Flutter UI
 // exactly like the real `Some(misc::Union::ChatMessage(c))` handler in
 // connection.rs, bypassing the need for the phone to actually type text.
 let body = request
 .split_once("\r\n\r\n")
 .map(|(_, body)| body)
 .unwrap_or_default();
 let payload = match serde_json::from_str::<serde_json::Value>(body) {
 Ok(payload) => payload,
 Err(_) => {
 respond(&mut stream, 400, json!({"error": "invalid_json"}));
 return;
 }
 };
 let peer_id = payload
 .get("peer_id")
 .and_then(serde_json::Value::as_str)
 .unwrap_or_default()
 .trim();
 let text = payload
 .get("text")
 .and_then(serde_json::Value::as_str)
 .unwrap_or_default();
 if peer_id.is_empty() || text.trim().is_empty() {
 respond(&mut stream, 400, json!({"error": "invalid_inject"}));
 return;
 }
 record_chat_event(
 "inject_chat",
 &format!("peer={} text_len={}", peer_id, text.len()),
 );
 #[cfg(feature = "flutter")]
 {
 if crate::common::is_main() {
 let event = serde_json::json!({
 "name": "chat_client_mode",
 "text": text.to_owned(),
 "peer_id": peer_id.to_owned(),
 })
 .to_string();
 crate::flutter::push_global_event(
 crate::flutter::APP_TYPE_MAIN,
 event,
 );
 }
 }
 respond(&mut stream, 200, json!({"ok": true, "peer_id": peer_id, "injected": true}));
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
            let permissions = PERMISSIONS.read().unwrap().clone();
            let input_events = INPUT_EVENTS.read().unwrap().clone();
            respond(
                &mut stream,
                200,
                json!({"sessions": sessions, "permissions": permissions, "input_events": input_events}),
            );
        }
        "/v1/chat-messages" => {
            let messages = CHAT_MESSAGES.read().unwrap().clone();
            respond(&mut stream, 200, json!({"messages": messages}));
        }
        _ => respond(&mut stream, 404, json!({"error": "not_found"})),
    }
}

fn respond(stream: &mut TcpStream, status: u16, body: serde_json::Value) {
    let body = body.to_string();
    let reason = match status {
        200 => "OK",
        400 => "Bad Request",
        409 => "Conflict",
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

    fn request_once_segments(parts: &[&str], token: &str) -> String {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let address = listener.local_addr().unwrap();
        let token = token.to_owned();
        let server = thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            serve(stream, &token);
        });
        let mut client = TcpStream::connect(address).unwrap();
        for part in parts {
            client.write_all(part.as_bytes()).unwrap();
        }
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

    #[test]
    fn chat_endpoint_rejects_unknown_sessions() {
        let body = r#"{"peer_id":"missing-peer","text":"probe"}"#;
        let header = format!(
            "POST /v1/chat HTTP/1.1\r\nauthorization: Bearer test-token\r\ncontent-type: application/json\r\ncontent-length: {}\r\n\r\n",
            body.len()
        );
        let split = body.len() / 2;
        let response = request_once_segments(
            &[&header, &body[..split], &body[split..]],
            "test-token",
        );
        assert!(response.starts_with("HTTP/1.1 404"));
        assert!(response.contains("session_not_found"));
    }

    #[test]
    fn chat_endpoint_rejects_unknown_sessions_with_legacy_request() {
        let response = request_once(
            "POST /v1/chat HTTP/1.1\r\nauthorization: Bearer test-token\r\ncontent-type: application/json\r\ncontent-length: 50\r\n\r\n{\"peer_id\":\"missing-peer\",\"text\":\"probe\"}",
            "test-token",
        );
        assert!(response.starts_with("HTTP/1.1 404"));
        assert!(response.contains("\"error\":\"session_not_found\""));
    }
}
