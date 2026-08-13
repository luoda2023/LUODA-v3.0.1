use std::{
    net::SocketAddr,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, RwLock,
    },
    time::{Duration, Instant},
};

use uuid::Uuid;

use hbb_common::{
    allow_err,
    anyhow::{self, bail},
    config::{
        self, keys::*, option2bool, use_ws, Config, LocalConfig, CONNECT_TIMEOUT,
        DEFAULT_DIRECT_PORT, REG_INTERVAL, RENDEZVOUS_PORT,
    },
    futures::future::join_all,
    log,
    protobuf::Message as _,
    rand::Rng,
    rendezvous_proto::*,
    sleep,
    socket_client::{self, connect_tcp, is_ipv4, new_direct_udp_for, new_udp_for},
    tokio::{self, select, sync::Mutex, time::interval},
    udp::FramedSocket,
    AddrMangle, IntoTargetAddr, ResultType, Stream, TargetAddr,
};

// Shorter registration interval for reconnection recovery (5s vs 15s).
const REG_INTERVAL_RECOVERY: i64 = 5_000;

use crate::{
    check_port,
    server::{check_zombie, new as new_server, ServerPtr},
};

type Message = RendezvousMessage;

/// Safe elapsed that never panics even if the monotonic clock jumps backwards
/// (e.g. on VMs or after sleep/hibernate), where `Instant::elapsed()` would
/// abort the whole process under `panic = "abort"`.
fn elapsed_safe(t: Instant) -> Duration {
    Instant::now().checked_duration_since(t).unwrap_or(Duration::ZERO)
}

lazy_static::lazy_static! {
    static ref SOLVING_PK_MISMATCH: Mutex<String> = Default::default();
    static ref LAST_MSG: Mutex<(SocketAddr, Instant)> = Mutex::new((SocketAddr::new([0; 4].into(), 0), Instant::now()));
    static ref LAST_RELAY_MSG: Mutex<(SocketAddr, Instant)> = Mutex::new((SocketAddr::new([0; 4].into(), 0), Instant::now()));
}
static SHOULD_EXIT: AtomicBool = AtomicBool::new(false);
static MANUAL_RESTARTED: AtomicBool = AtomicBool::new(false);
static SENT_REGISTER_PK: AtomicBool = AtomicBool::new(false);

fn normalize_transport_options() {
    #[cfg(target_os = "windows")]
    if crate::platform::windows::is_win_server() {
        Config::set_option(OPTION_ALLOW_WEBSOCKET.to_owned(), "N".to_owned());
        // Ensure direct IP access listener is always enabled on Windows Server
        // so that remote peers can connect via IP:port without a rendezvous server.
        if Config::get_option(OPTION_DIRECT_SERVER).is_empty() {
            Config::set_option(OPTION_DIRECT_SERVER.to_owned(), "Y".to_owned());
            log::info!("Windows Server: auto-enabled direct-server for IP access");
        }
        return;
    }
    // Enable the direct IP listener by default on ALL platforms so that
    // LAN peers can establish chat and file-transfer connections without
    // needing the rendezvous server to punch holes. Users who don't want
    // this can set direct-server to "N" explicitly in the UI settings.
    if Config::get_option(OPTION_DIRECT_SERVER).is_empty() {
        Config::set_option(OPTION_DIRECT_SERVER.to_owned(), "Y".to_owned());
        log::info!("Auto-enabled direct-server listener for LAN peer access");
    }
    if use_ws() && crate::is_udp_disabled() {
        Config::set_option(OPTION_ALLOW_WEBSOCKET.to_owned(), "N".to_owned());
        log::warn!("Disable UDP and WebSocket were both enabled; keeping raw TCP registration");
    }
}

#[derive(Clone)]
pub struct RendezvousMediator {
    addr: TargetAddr<'static>,
    host: String,
    host_prefix: String,
    keep_alive: i32,
}

impl RendezvousMediator {
    pub fn restart() {
        SHOULD_EXIT.store(true, Ordering::SeqCst);
        MANUAL_RESTARTED.store(true, Ordering::SeqCst);
        log::info!("server restart");
    }

    pub async fn start_all() {
        normalize_transport_options();
        // LUODA fix: a stale `serverless-direct-only=Y` (left by earlier serverless
        // experiments or a cloned config) skips rendezvous registration AND the
        // proactive --cm connection-manager start, leaving the device stuck at
        // "direct listening" and unreachable by ID for chat and remote assistance.
        // Clear it at the very top of start_all so every downstream check runs in
        // normal online mode.
        if Config::get_option(OPTION_SERVERLESS_DIRECT_ONLY) == "Y" {
            log::warn!("start_all: clearing stale serverless-direct-only=Y so the device registers");
            Config::set_option(OPTION_SERVERLESS_DIRECT_ONLY.to_owned(), String::new());
        }

        #[cfg(target_os = "windows")]
        if std::env::var_os(crate::common::PORTABLE_APPNAME_RUNTIME_ENV_KEY).is_some() {
            // Portable mode: only attempt headless virtual display when no
            // physical displays are present (i.e. running on a headless VPS).
            // On a normal desktop with a monitor, skip this to avoid screen flash.
            let has_physical_display = scrap::Display::all()
                .map(|d| !d.is_empty())
                .unwrap_or(false);
            if !has_physical_display {
                for attempt in 1..=3 {
                    match crate::server::display_service::prepare_windows_server_headless_display()
                    {
                        Ok(()) => {
                            log::info!("portable VPS virtual display ready (attempt {attempt})");
                            break;
                        }
                        Err(error) => {
                            log::error!(
                                "failed to prepare the portable VPS virtual display (attempt {attempt}/3): {error}"
                            );
                            if attempt < 3 {
                                std::thread::sleep(std::time::Duration::from_secs(2));
                            }
                        }
                    }
                }
            } else {
                log::info!("portable mode: physical display detected, skipping virtual display creation");
            }
        }
        if !crate::is_serverless_direct_only() {
            crate::test_nat_type();
        }
        if config::is_outgoing_only() {
            loop {
                sleep(1.).await;
            }
        }
        // LUODA builds also report presence to the API server (device registry),
        // so peers that consult the server-side peer list see this device online.
        log::info!("DBG start_all: after test_nat_type/outgoing check");
        crate::hbbs_http::sync::start();
        log::info!("DBG start_all: hbbs_http started");
        check_zombie();
        let server = new_server();
        log::info!("DBG start_all: new_server done");
        if !crate::is_luoda()
            && config::option2bool("stop-service", &Config::get_option("stop-service"))
        {
            crate::test_rendezvous_server();
        }
        let server_cloned = server.clone();
        tokio::spawn(async move {
            direct_server(server_cloned).await;
        });
        // LUODA: proactively start the connection manager (--cm) so the app is
        // immediately reachable and the UI shows "Online" right away. Without
        // this, the _cm IPC server only comes up after the first inbound
        // connection, leaving the status stuck at "Direct listening" and
        // inbound messages unprocessed until then.
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        if !crate::is_serverless_direct_only()
            && !crate::common::is_cm()
            && !crate::check_process("--cm", false)
        {
            match crate::run_me(vec!["--cm"]) {
                Ok(child) => {
                    crate::server::CHILD_PROCESS.lock().unwrap().push(child);
                    log::info!("start_all: proactively started --cm connection manager");
                }
                Err(err) => {
                    log::warn!("start_all: failed to start --cm: {}", err);
                }
            }
        }
        // LUODA: watchdog keeps the connection manager (--cm) resident. If the
        // CM window is closed or the process exits for any reason, inbound
        // chat/remote requests silently stall ("direct listening" forever,
        // messages need a manual P2P poke to arrive). Probe the _cm IPC pipe
        // every 10s and relaunch the CM when it is gone.
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        if !crate::is_serverless_direct_only() && !crate::common::is_cm() {
            tokio::spawn(async move {
                loop {
                    sleep(10.).await;
                    let cm_reachable = crate::ipc::connect(1000, "_cm").await.is_ok();
                    if cm_reachable || crate::check_process("--cm", false) {
                        continue;
                    }
                    log::warn!("cm watchdog: connection manager not reachable, restarting --cm");
                    if let Ok(child) = crate::run_me(vec!["--cm"]) {
                        crate::server::CHILD_PROCESS.lock().unwrap().push(child);
                    }
                }
            });
        }
        #[cfg(target_os = "android")]
        let start_lan_listening = true;
        #[cfg(target_os = "ios")]
        let start_lan_listening = false;
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        let start_lan_listening = true;
        if start_lan_listening {
            std::thread::spawn(move || {
                allow_err!(super::lan::start_listening());
            });
            // LUODA: periodic LAN discovery keeps direct pairings fresh when
            // direct-access ports are randomized per machine (DHCP changes too).
            // Without it, stored ip:port endpoints go stale and ID connections
            // degrade to relay/punch, which may fail for LAN peers.
            if config::option2bool(
                "enable-lan-discovery",
                &Config::get_option("enable-lan-discovery"),
            ) {
                std::thread::spawn(|| loop {
                    std::thread::sleep(std::time::Duration::from_secs(30));
                    allow_err!(super::lan::discover());
                });
            }
        }
        log::info!("DBG start_all: lan spawned");
        // It is ok to run xdesktop manager when the headless function is not allowed.
        #[cfg(target_os = "linux")]
        if crate::is_server() {
            crate::platform::linux_desktop_manager::start_xdesktop();
        }
        scrap::codec::test_av1();
                // LUODA fix: a stale `stop-service=Y` (left by an earlier uninstall or
        // a previous "stop service" toggle) must not silently cripple a freshly
        // started server. The UI toggle still stops the *current* session via
        // RendezvousMediator::restart(); on the next start the device should be
        // online again, otherwise B/C devices stay stuck at "direct listening"
        // forever and incoming chat/remote requests never arrive.
        if Config::get_option("stop-service") == "Y" {
            log::warn!("start_all: clearing stale stop-service=Y so the server registers");
            Config::set_option("stop-service".to_owned(), String::new());
        }
        log::info!("DBG start_all: test_av1 done, entering loop");
        loop {
            if crate::is_serverless_direct_only() {
                log::info!("LDesk serverless mode: direct listener and LAN discovery only");
                while crate::is_serverless_direct_only() {
                    sleep(1.).await;
                }
                crate::test_nat_type();
            }
            let timeout = Arc::new(RwLock::new(CONNECT_TIMEOUT));
            let conn_start_time = Instant::now();
            *SOLVING_PK_MISMATCH.lock().await = "".to_owned();
            if !config::option2bool("stop-service", &Config::get_option("stop-service"))
                && !crate::platform::installing_service()
            {
                let mut futs = Vec::new();
                let servers = Config::get_rendezvous_servers();
                log::info!("DBG loop: rendezvous servers = {:?}, stop-service={}, installing={}", servers, config::option2bool("stop-service", &Config::get_option("stop-service")), crate::platform::installing_service());
                SHOULD_EXIT.store(false, Ordering::SeqCst);
                MANUAL_RESTARTED.store(false, Ordering::SeqCst);
                for host in servers.clone() {
                    let server = server.clone();
                    let timeout = timeout.clone();
                    futs.push(tokio::spawn(async move {
                        if let Err(err) = Self::start(server, host).await {
                            let err = format!("rendezvous mediator error: {err}");
                            // When user reboot, there might be below error, waiting too long
                            // (CONNECT_TIMEOUT 18s) will make user think there is bug
                            if err.contains("10054") || err.contains("11001") {
                                // No such host is known. (os error 11001)
                                // An existing connection was forcibly closed by the remote host. (os error 10054): also happens for UDP
                                *timeout.write().unwrap() = 3000;
                            }
                            log::error!("{err}");
                        }
                        // SHOULD_EXIT here is to ensure once one exits, the others also exit.
                        SHOULD_EXIT.store(true, Ordering::SeqCst);
                    }));
                }
                join_all(futs).await;
            } else {
                server.write().unwrap().close_connections();
            }
            Config::reset_online();
            let timeout = *timeout.read().unwrap();
            if !MANUAL_RESTARTED.load(Ordering::SeqCst) {
                let elapsed = elapsed_safe(conn_start_time).as_millis() as u64;
                if elapsed < timeout {
                    sleep(((timeout - elapsed) / 1000) as _).await;
                }
            } else {
                // https://github.com/luoda/luoda/issues/12233
                sleep(0.033).await;
            }
        }
    }

    fn get_host_prefix(host: &str) -> String {
        host.split(".")
            .next()
            .map(|x| {
                if x.parse::<i32>().is_ok() {
                    host.to_owned()
                } else {
                    x.to_owned()
                }
            })
            .unwrap_or(host.to_owned())
    }

    pub async fn start_udp(server: ServerPtr, host: String) -> ResultType<()> {
        let host = check_port(&host, RENDEZVOUS_PORT);
        log::info!("start udp: {host}");
        let (mut socket, mut addr) = new_udp_for(&host, CONNECT_TIMEOUT).await?;
        let mut rz = Self {
            addr: addr.clone(),
            host: host.clone(),
            host_prefix: Self::get_host_prefix(&host),
            keep_alive: crate::DEFAULT_KEEP_ALIVE,
        };

        let mut timer = crate::luoda_interval(interval(crate::TIMER_OUT));
        const MIN_REG_TIMEOUT: i64 = 3_000;
        const MAX_REG_TIMEOUT: i64 = 30_000;
        let mut reg_timeout = MIN_REG_TIMEOUT;
        const MAX_FAILS1: i64 = 2;
        const MAX_FAILS2: i64 = 4;
        const DNS_INTERVAL: i64 = 60_000;
        let mut fails = 0;
        let mut last_register_resp: Option<Instant> = None;
        let mut last_register_sent: Option<Instant> = None;
        let mut last_dns_check = Instant::now();
        let mut old_latency = 0;
        let mut ema_latency = 0;
        loop {
            let mut update_latency = || {
                last_register_resp = Some(Instant::now());
                fails = 0;
                reg_timeout = MIN_REG_TIMEOUT;
                let mut latency = last_register_sent
                    .map(|x| elapsed_safe(x).as_micros() as i64)
                    .unwrap_or(0);
                last_register_sent = None;
                if latency < 0 || latency > 1_000_000 {
                    return;
                }
                if ema_latency == 0 {
                    ema_latency = latency;
                } else {
                    ema_latency = latency / 30 + (ema_latency * 29 / 30);
                    latency = ema_latency;
                }
                let mut n = latency / 5;
                if n < 3000 {
                    n = 3000;
                }
                if (latency - old_latency).abs() > n || old_latency <= 0 {
                    Config::update_latency(&host, latency);
                    log::debug!("Latency of {}: {}ms", host, latency as f64 / 1000.);
                    old_latency = latency;
                }
            };
            select! {
                n = socket.next() => {
                    match n {
                        Some(Ok((bytes, _))) => {
                            if let Ok(msg) = Message::parse_from_bytes(&bytes) {
                                rz.handle_resp(msg.union, Sink::Framed(&mut socket, &addr), &server, &mut update_latency).await?;
                            } else {
                                log::debug!("Non-protobuf message bytes received: {:?}", bytes);
                            }
                        },
                        Some(Err(e)) => bail!("Failed to receive next: {}", e),  // maybe socks5 tcp disconnected
                        None => {
                            bail!("Socket receive none. Maybe socks5 server is down.");
                        },
                    }
                },
                _ = timer.tick() => {
                    if SHOULD_EXIT.load(Ordering::SeqCst) {
                        break;
                    }
                    let now = Some(Instant::now());
                    // Use shorter interval when re-registering after disconnect
                    let expired = last_register_resp
                        .map(|x| elapsed_safe(x).as_millis() as i64 >= REG_INTERVAL_RECOVERY)
                        .unwrap_or(true);
                    let timeout = last_register_sent.map(|x| elapsed_safe(x).as_millis() as i64 >= reg_timeout).unwrap_or(false);
                    // temporarily disable exponential backoff for android before we add wakeup trigger to force connect in android
                    #[cfg(not(any(target_os = "android", target_os = "ios")))]
                    if crate::using_public_server() { // only turn on this for public server, may help DDNS self-hosting user.
                        if timeout && reg_timeout < MAX_REG_TIMEOUT {
                            reg_timeout += MIN_REG_TIMEOUT;
                        }
                    }
                    if timeout || (last_register_sent.is_none() && expired) {
                        if timeout {
                            fails += 1;
                            if fails >= MAX_FAILS2 {
                                Config::update_latency(&host, -1);
                                old_latency = 0;
                                log::warn!(
                                    "Rendezvous server {} not responding over UDP after {} attempts, switching to TCP",
                                    host, fails
                                );
                                if elapsed_safe(last_dns_check).as_millis() as i64 > DNS_INTERVAL {
                                    // in some case of network reconnect (dial IP network),
                                    // old UDP socket not work any more after network recover
                                    if let Some((s, new_addr)) = socket_client::rebind_udp_for(&rz.host).await? {
                                        socket = s;
                                        rz.addr = new_addr.clone();
                                        addr = new_addr;
                                    }
                                    last_dns_check = Instant::now();
                                }
                                bail!("UDP rendezvous registration timed out");
                            } else if fails >= MAX_FAILS1 {
                                Config::update_latency(&host, 0);
                                old_latency = 0;
                            }
                        }
                        rz.register_peer(Sink::Framed(&mut socket, &addr)).await?;
                        last_register_sent = now;
                    }
                }
            }
        }
        Ok(())
    }

    #[inline]
    async fn handle_resp(
        &mut self,
        msg: Option<rendezvous_message::Union>,
        sink: Sink<'_>,
        server: &ServerPtr,
        update_latency: &mut impl FnMut(),
    ) -> ResultType<()> {
        match msg {
            Some(rendezvous_message::Union::RegisterPeerResponse(rpr)) => {
                update_latency();
                if rpr.request_pk {
                    log::info!("request_pk received from {}", self.host);
                    self.register_pk(sink).await?;
                }
            }
            Some(rendezvous_message::Union::RegisterPkResponse(rpr)) => {
                update_latency();
                match rpr.result.enum_value() {
                    Ok(register_pk_response::Result::OK) => {
                        Config::set_key_confirmed(true);
                        Config::set_host_key_confirmed(&self.host_prefix, true);
                        *SOLVING_PK_MISMATCH.lock().await = "".to_owned();
                        self.register_peer(sink).await?;
                    }
                    Ok(register_pk_response::Result::UUID_MISMATCH) => {
                        self.handle_uuid_mismatch(sink).await?;
                    }
                    _ => {
                        log::error!("unknown RegisterPkResponse");
                    }
                }
                if rpr.keep_alive > 0 {
                    self.keep_alive = rpr.keep_alive * 1000;
                    log::info!("keep_alive: {}ms", self.keep_alive);
                }
            }
            Some(rendezvous_message::Union::PunchHole(ph)) => {
                let rz = self.clone();
                let server = server.clone();
                tokio::spawn(async move {
                    allow_err!(rz.handle_punch_hole(ph, server).await);
                });
            }
            Some(rendezvous_message::Union::RequestRelay(rr)) => {
                let rz = self.clone();
                let server = server.clone();
                tokio::spawn(async move {
                    allow_err!(rz.handle_request_relay(rr, server).await);
                });
            }
            Some(rendezvous_message::Union::FetchLocalAddr(fla)) => {
                let rz = self.clone();
                let server = server.clone();
                tokio::spawn(async move {
                    allow_err!(rz.handle_intranet(fla, server).await);
                });
            }
            Some(rendezvous_message::Union::ConfigureUpdate(cu)) => {
                let v0 = Config::get_rendezvous_servers();
                Config::set_option(
                    "rendezvous-servers".to_owned(),
                    cu.rendezvous_servers.join(","),
                );
                Config::set_serial(cu.serial);
                if v0 != Config::get_rendezvous_servers() {
                    Self::restart();
                }
            }
            _ => {}
        }
        Ok(())
    }

    pub async fn start_tcp(server: ServerPtr, host: String) -> ResultType<()> {
        let host = check_port(&host, RENDEZVOUS_PORT);
        log::info!("start tcp: {}", hbb_common::websocket::check_ws(&host));
        let mut conn = match connect_tcp(host.clone(), CONNECT_TIMEOUT).await {
            Ok(c) => c,
            Err(e) => {
                log::error!("Failed to connect to rendezvous server {}: {}", host, e);
                return Err(e);
            }
        };
        let key = crate::get_key(true).await;
        if let Err(e) = crate::secure_tcp(&mut conn, &key).await {
            log::error!("Key exchange failed with {}: {}", host, e);
            return Err(e);
        }
        let mut rz = Self {
            addr: conn.local_addr().into_target_addr()?,
            host: host.clone(),
            host_prefix: Self::get_host_prefix(&host),
            keep_alive: crate::DEFAULT_KEEP_ALIVE,
        };
        let mut timer = crate::luoda_interval(interval(crate::TIMER_OUT));
        let mut last_register_sent: Option<Instant> = None;
        let mut last_recv_msg = Instant::now();
        let mut register_fail_count: u32 = 0;
        // we won't support connecting to multiple rendzvous servers any more, so we can use a global variable here.
        Config::set_host_key_confirmed(&rz.host_prefix, false);
        log::info!("TCP rendezvous connected to {}, starting registration loop", host);
        loop {
            let mut update_latency = || {
                let latency = last_register_sent
                    .map(|x| elapsed_safe(x).as_micros() as i64)
                    .unwrap_or(0);
                Config::update_latency(&host, latency);
                log::debug!("Latency of {}: {}ms", host, latency as f64 / 1000.);
            };
            select! {
                res = conn.next() => {
                    last_recv_msg = Instant::now();
                    let bytes = res.ok_or_else(|| anyhow::anyhow!("Rendezvous connection is reset by the peer"))??;
                    if bytes.is_empty() {
                        // After fixing frequent register_pk, for websocket, nginx need to set proxy_read_timeout to more than 60 seconds, eg: 120s
                        // https://serverfault.com/questions/1060525/why-is-my-websocket-connection-gets-closed-in-60-seconds
                        conn.send_bytes(bytes::Bytes::new()).await?;
                        continue; // heartbeat
                    }
                    let msg = Message::parse_from_bytes(&bytes)?;
                    rz.handle_resp(msg.union, Sink::Stream(&mut conn), &server, &mut update_latency).await?
                }
                _ = timer.tick() => {
                    if SHOULD_EXIT.load(Ordering::SeqCst) {
                        break;
                    }
                    // https://www.emqx.com/en/blog/mqtt-keep-alive
                    if elapsed_safe(last_recv_msg).as_millis() as u64 > rz.keep_alive as u64 * 3 / 2 {
                        log::error!("Rendezvous connection to {} timed out (no response for {}ms)",
                            host, rz.keep_alive as u64 * 3 / 2);
                        bail!("Rendezvous connection is timeout");
                    }
                    if last_register_sent.map(|x| elapsed_safe(x).as_millis() as i64).unwrap_or(REG_INTERVAL_RECOVERY) >= REG_INTERVAL_RECOVERY {
                        let key_confirmed = Config::get_key_confirmed();
                        let host_key_confirmed = Config::get_host_key_confirmed(&rz.host_prefix);
                        if !key_confirmed || !host_key_confirmed {
                            register_fail_count += 1;
                            if register_fail_count % 4 == 1 {
                                log::warn!(
                                    "Key not confirmed for {} (global={}, host={}), attempt {}",
                                    rz.host_prefix, key_confirmed, host_key_confirmed, register_fail_count
                                );
                            }
                            // After 8 failed attempts (~2 min), force reset key confirmation
                            // to recover from a stuck state.
                            if register_fail_count == 8 {
                                log::warn!("Forcing key re-registration for {} after {} failed attempts",
                                    rz.host_prefix, register_fail_count);
                                Config::set_key_confirmed(false);
                                Config::set_host_key_confirmed(&rz.host_prefix, false);
                            }
                            rz.register_pk(Sink::Stream(&mut conn)).await?;
                        } else {
                            register_fail_count = 0;
                            rz.register_peer(Sink::Stream(&mut conn)).await?;
                        }
                        last_register_sent = Some(Instant::now());
                    }
                }
            }
        }
        Ok(())
    }

    pub async fn start(server: ServerPtr, host: String) -> ResultType<()> {
        log::info!("start rendezvous mediator of {}", host);
        #[cfg(target_os = "windows")]
        let windows_server = crate::platform::windows::is_win_server();
        #[cfg(not(target_os = "windows"))]
        let windows_server = false;
        if should_use_tcp_rendezvous(
            windows_server,
            cfg!(debug_assertions) && option_env!("TEST_TCP").is_some(),
            Config::is_proxy(),
            use_ws(),
            crate::is_udp_disabled(),
        ) {
            Self::start_tcp(server, host).await
        } else {
            // Try UDP first (lower latency, enables hole punching). Some
            // networks/cloud firewalls silently drop outbound UDP, which would
            // leave the device permanently "offline" (status 0 -> direct
            // listening only). Fall back to TCP registration in that case so
            // presence and ID-based discovery keep working everywhere.
            match Self::start_udp(server.clone(), host.clone()).await {
                Ok(()) => Ok(()),
                Err(err) => {
                    log::warn!("UDP rendezvous failed, falling back to TCP: {}", err);
                    Self::start_tcp(server, host).await
                }
            }
        }
    }

    async fn handle_request_relay(&self, rr: RequestRelay, server: ServerPtr) -> ResultType<()> {
        let addr = AddrMangle::decode(&rr.socket_addr);
        let last = *LAST_RELAY_MSG.lock().await;
        *LAST_RELAY_MSG.lock().await = (addr, Instant::now());
        // skip duplicate relay request messages
        if last.0 == addr && elapsed_safe(last.1).as_millis() < 100 {
            return Ok(());
        }

        self.create_relay(
            rr.socket_addr.into(),
            rr.relay_server,
            rr.uuid,
            server,
            rr.secure,
            false,
            Default::default(),
            rr.control_permissions.clone().into_option(),
        )
        .await
    }

    async fn create_relay(
        &self,
        socket_addr: Vec<u8>,
        relay_server: String,
        uuid: String,
        server: ServerPtr,
        secure: bool,
        initiate: bool,
        socket_addr_v6: bytes::Bytes,
        control_permissions: Option<ControlPermissions>,
    ) -> ResultType<()> {
        let peer_addr = AddrMangle::decode(&socket_addr);
        log::info!(
            "create_relay requested from {:?}, relay_server: {}, uuid: {}, secure: {}",
            peer_addr,
            relay_server,
            uuid,
            secure,
        );

        let mut socket = connect_tcp(&*self.host, CONNECT_TIMEOUT).await?;

        let mut msg_out = Message::new();
        let mut rr = RelayResponse {
            socket_addr: socket_addr.into(),
            version: crate::VERSION.to_owned(),
            socket_addr_v6,
            ..Default::default()
        };
        if initiate {
            rr.uuid = uuid.clone();
            rr.relay_server = relay_server.clone();
            rr.set_id(Config::get_id());
        }
        msg_out.set_relay_response(rr);
        socket.send(&msg_out).await?;
        crate::create_relay_connection(
            server,
            relay_server,
            uuid,
            peer_addr,
            secure,
            is_ipv4(&self.addr),
            control_permissions,
        )
        .await;
        Ok(())
    }

    async fn handle_intranet(&self, fla: FetchLocalAddr, server: ServerPtr) -> ResultType<()> {
        let addr = AddrMangle::decode(&fla.socket_addr);
        let last = *LAST_MSG.lock().await;
        *LAST_MSG.lock().await = (addr, Instant::now());
        // skip duplicate punch hole messages
        if last.0 == addr && elapsed_safe(last.1).as_millis() < 100 {
            return Ok(());
        }
        let peer_addr_v6 = hbb_common::AddrMangle::decode(&fla.socket_addr_v6);
        let relay_server = self.get_relay_server(fla.relay_server.clone());
        let relay = use_ws() || Config::is_proxy();
        let mut socket_addr_v6 = Default::default();
        if peer_addr_v6.port() > 0 && !relay {
            socket_addr_v6 = start_ipv6(
                peer_addr_v6,
                addr,
                server.clone(),
                fla.control_permissions.clone().into_option(),
            )
            .await;
        }
        let is_private_ipv4 = match &self.addr {
            TargetAddr::Ip(addr) => match addr.ip() {
                std::net::IpAddr::V4(v4) => v4.is_private(),
                _ => false,
            },
            _ => false,
        };
        if is_ipv4(&self.addr) && !relay
            && (!config::is_disable_tcp_listen() || is_private_ipv4)
        {
            if let Err(err) = self
                .handle_intranet_(
                    fla.clone(),
                    server.clone(),
                    relay_server.clone(),
                    socket_addr_v6.clone(),
                )
                .await
            {
                log::debug!("Failed to handle intranet: {:?}, will try relay", err);
            } else {
                return Ok(());
            }
        }
        let uuid = Uuid::new_v4().to_string();
        self.create_relay(
            fla.socket_addr.into(),
            relay_server,
            uuid,
            server,
            true,
            true,
            socket_addr_v6,
            fla.control_permissions.into_option(),
        )
        .await
    }

    async fn handle_intranet_(
        &self,
        fla: FetchLocalAddr,
        server: ServerPtr,
        relay_server: String,
        socket_addr_v6: bytes::Bytes,
    ) -> ResultType<()> {
        let peer_addr = AddrMangle::decode(&fla.socket_addr);
        log::debug!("Handle intranet from {:?}", peer_addr);
        let mut socket = connect_tcp(&*self.host, CONNECT_TIMEOUT).await?;
        let local_addr = socket.local_addr();
        // we saw invalid local_addr while using proxy, local_addr.ip() == "::1"
        let local_addr: SocketAddr =
            format!("{}:{}", local_addr.ip(), local_addr.port()).parse()?;
        let mut msg_out = Message::new();
        msg_out.set_local_addr(LocalAddr {
            id: Config::get_id(),
            socket_addr: AddrMangle::encode(peer_addr).into(),
            local_addr: AddrMangle::encode(local_addr).into(),
            relay_server,
            version: crate::VERSION.to_owned(),
            socket_addr_v6,
            ..Default::default()
        });
        let bytes = msg_out.write_to_bytes()?;
        socket.send_raw(bytes).await?;
        crate::accept_connection(
            server.clone(),
            socket,
            peer_addr,
            true,
            fla.control_permissions.into_option(),
        )
        .await;
        Ok(())
    }

    async fn handle_punch_hole(&self, ph: PunchHole, server: ServerPtr) -> ResultType<()> {
        let mut peer_addr = AddrMangle::decode(&ph.socket_addr);
        let last = *LAST_MSG.lock().await;
        *LAST_MSG.lock().await = (peer_addr, Instant::now());
        // skip duplicate punch hole messages
        if last.0 == peer_addr && elapsed_safe(last.1).as_millis() < 100 {
            return Ok(());
        }
        let peer_addr_v6 = hbb_common::AddrMangle::decode(&ph.socket_addr_v6);
        let relay = use_ws() || Config::is_proxy() || ph.force_relay;
        let mut socket_addr_v6 = Default::default();
        let control_permissions = ph.control_permissions.into_option();
        if peer_addr_v6.port() > 0 && !relay {
            socket_addr_v6 = start_ipv6(
                peer_addr_v6,
                peer_addr,
                server.clone(),
                control_permissions.clone(),
            )
            .await;
        }
        let relay_server = self.get_relay_server(ph.relay_server);
        // LUODA: a punching peer whose address is not on a private LAN can never
        // reach our direct listener (most routers have no port forwarding / UPnP).
        // Always relay for such remote peers, otherwise the initiator wastes its
        // whole direct-attempt timeout and the relay handshake times out.
        let peer_is_remote = !crate::common::is_lan_ip(&peer_addr.ip().to_string());
        // for ensure, websocket go relay directly
        if ph.nat_type.enum_value() == Ok(NatType::SYMMETRIC)
            || Config::get_nat_type() == NatType::SYMMETRIC as i32
            || relay
            || peer_is_remote
            || (config::is_disable_tcp_listen() && ph.udp_port <= 0)
        {
            let uuid = Uuid::new_v4().to_string();
            return self
                .create_relay(
                    ph.socket_addr.into(),
                    relay_server,
                    uuid,
                    server,
                    true,
                    true,
                    socket_addr_v6.clone(),
                    control_permissions,
                )
                .await;
        }
        use hbb_common::protobuf::Enum;
        let nat_type = NatType::from_i32(Config::get_nat_type()).unwrap_or(NatType::UNKNOWN_NAT);
        let msg_punch = PunchHoleSent {
            socket_addr: ph.socket_addr,
            id: Config::get_id(),
            relay_server,
            nat_type: nat_type.into(),
            version: crate::VERSION.to_owned(),
            socket_addr_v6,
            ..Default::default()
        };
        if ph.udp_port > 0 {
            peer_addr.set_port(ph.udp_port as u16);
            self.punch_udp_hole(peer_addr, server, msg_punch, control_permissions)
                .await?;
            return Ok(());
        }
        log::debug!("Punch tcp hole to {:?}", peer_addr);
        let mut socket = {
            let socket = connect_tcp(&*self.host, CONNECT_TIMEOUT).await?;
            let local_addr = socket.local_addr();
            // key important here for punch hole to tell my gateway incoming peer is safe.
            // it can not be async here, because local_addr can not be reused, we must close the connection before use it again.
            allow_err!(socket_client::connect_tcp_local(peer_addr, Some(local_addr), 30).await);
            socket
        };
        let mut msg_out = Message::new();
        msg_out.set_punch_hole_sent(msg_punch);
        let bytes = msg_out.write_to_bytes()?;
        socket.send_raw(bytes).await?;
        crate::accept_connection(server.clone(), socket, peer_addr, true, control_permissions)
            .await;
        Ok(())
    }

    async fn punch_udp_hole(
        &self,
        peer_addr: SocketAddr,
        server: ServerPtr,
        msg_punch: PunchHoleSent,
        control_permissions: Option<ControlPermissions>,
    ) -> ResultType<()> {
        let mut msg_out = Message::new();
        msg_out.set_punch_hole_sent(msg_punch);
        let (socket, addr) = new_direct_udp_for(&self.host).await?;
        let data = msg_out.write_to_bytes()?;
        socket.send_to(&data, addr).await?;
        let socket_cloned = socket.clone();
        tokio::spawn(async move {
            for _ in 0..2 {
                let tm = (hbb_common::time_based_rand() % 20 + 10) as f32 / 1000.;
                hbb_common::sleep(tm).await;
                socket.send_to(&data, addr).await.ok();
            }
        });
        udp_nat_listen(
            socket_cloned.clone(),
            peer_addr,
            peer_addr,
            server,
            control_permissions,
        )
        .await?;
        Ok(())
    }

    async fn register_pk(&mut self, socket: Sink<'_>) -> ResultType<()> {
        let mut msg_out = Message::new();
        let pk = Config::get_key_pair().1;
        let uuid = hbb_common::get_uuid();
        let id = Config::get_id();
        msg_out.set_register_pk(RegisterPk {
            id,
            uuid: uuid.into(),
            pk: pk.into(),
            no_register_device: Config::no_register_device(),
            ..Default::default()
        });
        socket.send(&msg_out).await?;
        SENT_REGISTER_PK.store(true, Ordering::SeqCst);
        Ok(())
    }

    async fn handle_uuid_mismatch(&mut self, socket: Sink<'_>) -> ResultType<()> {
        {
            let mut solving = SOLVING_PK_MISMATCH.lock().await;
            if solving.is_empty() || *solving == self.host {
                log::info!("UUID_MISMATCH received from {}", self.host);
                Config::set_key_confirmed(false);
                Config::update_id();
                *solving = self.host.clone();
            } else {
                return Ok(());
            }
        }
        self.register_pk(socket).await
    }

    async fn register_peer(&mut self, socket: Sink<'_>) -> ResultType<()> {
        let solving = SOLVING_PK_MISMATCH.lock().await;
        if !(solving.is_empty() || *solving == self.host) {
            return Ok(());
        }
        drop(solving);
        if !Config::get_key_confirmed() || !Config::get_host_key_confirmed(&self.host_prefix) {
            log::info!(
                "SEND RegisterPk (handshake only, ID NOT registered yet): host={}, key_confirmed={}, host_key_confirmed={}",
                self.host_prefix,
                Config::get_key_confirmed(),
                Config::get_host_key_confirmed(&self.host_prefix)
            );
            return self.register_pk(socket).await;
        }
        let id = Config::get_id();
        log::info!(
            "SEND RegisterPeer (ID registered in online table): id={:?}, server={:?}, host={}",
            id,
            self.addr,
            self.host_prefix,
        );
        let mut msg_out = Message::new();
        let serial = Config::get_serial();
        msg_out.set_register_peer(RegisterPeer {
            id,
            serial,
            ..Default::default()
        });
        socket.send(&msg_out).await?;
        Ok(())
    }

    fn get_relay_server(&self, provided_by_rendezvous_server: String) -> String {
        let mut relay_server = Config::get_option("relay-server");
        if relay_server.is_empty() {
            relay_server = provided_by_rendezvous_server;
        }
        if relay_server.is_empty() {
            relay_server = crate::increase_port(&self.host, 1);
        }
        relay_server
    }
}

fn should_use_tcp_rendezvous(
    windows_server: bool,
    test_tcp: bool,
    proxy: bool,
    websocket: bool,
    udp_disabled: bool,
) -> bool {
    windows_server || test_tcp || proxy || websocket || udp_disabled
}

static DIRECT_PORT: std::sync::OnceLock<std::sync::Mutex<i32>> = std::sync::OnceLock::new();
const OPTION_DIRECT_LISTENER_STATUS: &str = "direct-listener-status";

fn set_direct_listener_status(status: &str) {
    if Config::get_option(OPTION_DIRECT_LISTENER_STATUS) != status {
        Config::set_option(OPTION_DIRECT_LISTENER_STATUS.to_owned(), status.to_owned());
        // The Flutter UI reads options through the in-memory cache
        // (ui_interface::get_option), so push the fresh value through it too.
        crate::ui_interface::refresh_options();
    }
}

/// Best-effort Windows firewall self-heal for the randomized direct port.
///
/// The legacy fixed port 20830 was covered by installer rules (21118-21128),
/// but a per-machine random port (20000-40000) is not. Without an inbound rule
/// the listener accepts nothing from other machines, which showed up as
/// "peer offline" / "A rejects messages" even though the rendezvous server
/// saw the peer online. Runs at most once per process; silently ignores
/// failures (needs elevation, which is available when installed).
#[cfg(windows)]
fn ensure_dynamic_firewall_rule() {
    use std::sync::OnceLock;
    static DONE: OnceLock<()> = OnceLock::new();
    if DONE.get().is_some() {
        return;
    }
    for (name, proto) in [
        ("LUODA Direct Access Dynamic TCP", "TCP"),
        ("LUODA Direct Access Dynamic UDP", "UDP"),
    ] {
        let status = std::process::Command::new("netsh")
            .args([
                "advfirewall",
                "firewall",
                "add",
                "rule",
                &format!("name={}", name),
                "dir=in",
                "action=allow",
                &format!("protocol={}", proto),
                "localport=20000-40000",
                "enable=yes",
            ])
            .output();
        match status {
            Ok(out) if out.status.success() => {
                log::info!("Firewall rule {} ensured", name);
            }
            Ok(out) => {
                log::warn!(
                    "Failed to ensure firewall rule {}: {}",
                    name,
                    String::from_utf8_lossy(&out.stderr).trim()
                );
            }
            Err(err) => {
                log::warn!("Failed to ensure firewall rule {}: {}", name, err);
            }
        }
    }
    let _ = DONE.set(());
}

#[cfg(not(windows))]
fn ensure_dynamic_firewall_rule() {}

fn parse_direct_port(value: &str) -> i32 {
    value
        .parse::<i32>()
        .ok()
        .filter(|port| (1..=u16::MAX as i32).contains(port))
        .unwrap_or(DEFAULT_DIRECT_PORT)
}

/// Stable per-machine identity used to derive the direct-access port.
///
/// The rendezvous server keys peers by ID but routes direct traffic by the
/// endpoint each peer publishes. Machines that share a copied config would
/// otherwise publish the *same* port behind the same public IP, which breaks
/// online status and direct routing. Deriving the port from a machine-scoped
/// seed (never part of the copied config) gives every machine a stable,
/// practically-unique port even when the whole config folder is cloned.
fn machine_port_seed() -> String {
    #[cfg(windows)]
    {
        use winreg::enums::HKEY_LOCAL_MACHINE;
        use winreg::RegKey;
        if let Ok(hk) = RegKey::predef(HKEY_LOCAL_MACHINE)
            .open_subkey("SOFTWARE\\Microsoft\\Cryptography")
        {
            if let Ok(guid) = hk.get_value::<String, _>("MachineGuid") {
                let guid = guid.trim();
                if !guid.is_empty() {
                    return format!("mguid:{guid}");
                }
            }
        }
        let hn = std::env::var("COMPUTERNAME").unwrap_or_default();
        let profile = std::env::var("USERPROFILE").unwrap_or_default();
        format!("host:{hn}:{profile}")
    }
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        // Mobile network interface addresses (wlan0 MAC) change due to MAC
        // randomization, which would re-roll the direct port on every Wi-Fi
        // reconnect and leave published endpoints out of sync with the actual
        // listener (peers then see the device as "rejecting" or "offline").
        // Persist a random seed in local config on first use so the port stays
        // stable across restarts, app updates and network changes.
        // The in-memory LocalConfig cache can be initialized before APP_DIR is
        // set (early Kotlin/Dart getLocalOption calls race with startServer),
        // which makes it look empty and re-rolls the seed/device id on every
        // cold start. When the app dir is valid, prefer the persisted file
        // value and adopt it into the cache so the identity stays stable.
        if !config::APP_DIR.read().unwrap().is_empty() {
            let from_file = LocalConfig::get_option_from_file("direct-port-machine-seed");
            let cached = LocalConfig::get_option("direct-port-machine-seed");
            if !from_file.is_empty() && from_file != cached {
                LocalConfig::set_option("direct-port-machine-seed".to_owned(), from_file.clone());
                return format!("seed:{from_file}");
            }
            if !cached.is_empty() {
                return format!("seed:{cached}");
            }
            if !from_file.is_empty() {
                return format!("seed:{from_file}");
            }
        } else {
            let cached = LocalConfig::get_option("direct-port-machine-seed");
            if !cached.is_empty() {
                return format!("seed:{cached}");
            }
        }
        let bytes: [u8; 16] = rand::thread_rng().gen();
        let generated = crate::encode64(bytes);
        LocalConfig::set_option("direct-port-machine-seed".to_owned(), generated.clone());
        log::info!("Assigned stable mobile direct-port seed");
        format!("seed:{generated}")
    }
    #[cfg(not(any(windows, target_os = "android", target_os = "ios")))]
    {
        for path in ["/etc/machine-id", "/sys/class/net/wlan0/address"] {
            if let Ok(s) = std::fs::read_to_string(path) {
                let s = s.trim().to_string();
                if !s.is_empty() {
                    return format!("seed:{s}");
                }
            }
        }
        std::env::var("HOSTNAME")
            .or_else(|_| std::env::var("COMPUTERNAME"))
            .unwrap_or_default()
    }
}

/// Map a machine seed to a stable port in 20000..40000 (FNV-1a).
fn machine_derived_port(seed: &str) -> i32 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for b in seed.bytes() {
        hash ^= u64::from(b);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    20000 + (hash % 20000) as i32
}

const OPTION_DIRECT_PORT_MACHINE_ID: &str = "direct-port-machine-id";

fn configured_direct_port() -> i32 {
    let stored = Config::get_option(OPTION_DIRECT_ACCESS_PORT);
    let port = parse_direct_port(&stored);
    let seed = machine_port_seed();
    let marker = Config::get_option(OPTION_DIRECT_PORT_MACHINE_ID);
    // The whole config folder was cloned from another machine when this marker
    // (written with a foreign machine seed) is present but does not match the
    // current machine. Cloned configs also carry the original machine's
    // rendezvous ID, so on hbbs only one of the machines stays online (the
    // others get stuck at "direct listening"), and inbound chat is dropped as
    // "self" because the copied chat device id matches. Re-roll the ID once so
    // every machine registers under its own identity.
    let config_cloned = !marker.is_empty() && !marker.eq_ignore_ascii_case(&seed);
    // Re-roll when: no port stored yet, the port is one of the legacy shared
    // fixed ports (20830 / 21118-21128), or the config was copied from another
    // machine (its machine marker does not match this machine's seed).
    if stored.is_empty()
        || port == 20830
        || (DEFAULT_DIRECT_PORT..=DEFAULT_DIRECT_PORT + 10).contains(&port)
        || !marker.eq_ignore_ascii_case(&seed)
    {
        let generated = machine_derived_port(&seed);
        Config::set_option(OPTION_DIRECT_ACCESS_PORT.to_owned(), generated.to_string());
        Config::set_option(OPTION_DIRECT_PORT_MACHINE_ID.to_owned(), seed.clone());
        if config_cloned && Config::get_option("id-machine-uid") != seed {
            let old_id = Config::get_id();
            Config::update_id();
            Config::set_option("id-machine-uid".to_owned(), seed.clone());
            // Tell the Flutter chat layer to re-roll its device id as well,
            // otherwise the cloned device keeps the original machine's device
            // id and the owner drops its messages as "self".
            LocalConfig::set_option(
                "direct-chat-identity-reset".to_owned(),
                "Y".to_owned(),
            );
            // Cloned configs can also carry the original machine's
            // serverless/stop-service flags and key pair. The serverless flag
            // skips rendezvous registration entirely (forever stuck at
            // "direct listening"); the copied key pair makes hbbs answer
            // UUID_MISMATCH. Force all of them off so this machine registers
            // under its own fresh identity.
            Config::set_option(OPTION_SERVERLESS_DIRECT_ONLY.to_owned(), String::new());
            Config::set_option("stop-service".to_owned(), String::new());
            Config::reset_key_pair();
            Config::set_key_confirmed(false);
            log::warn!(
                "config cloned from another machine: re-rolled rendezvous ID {} -> {} and chat identity",
                old_id,
                Config::get_id()
            );
        }
        ensure_dynamic_firewall_rule();
        log::info!(
            "Assigned machine-unique direct port {} (replacing {})",
            generated, port
        );
        generated
    } else {
        port
    }
}

#[cfg(test)]
mod direct_port_tests {
    use super::{parse_direct_port, should_use_tcp_rendezvous};
    use hbb_common::config::DEFAULT_DIRECT_PORT;

    #[test]
    fn accepts_configured_port() {
        assert_eq!(parse_direct_port("25488"), 25488);
        assert_eq!(parse_direct_port("65535"), 65535);
    }

    #[test]
    fn rejects_missing_or_out_of_range_port() {
        assert_eq!(parse_direct_port(""), DEFAULT_DIRECT_PORT);
        assert_eq!(parse_direct_port("0"), DEFAULT_DIRECT_PORT);
        assert_eq!(parse_direct_port("65536"), DEFAULT_DIRECT_PORT);
    }

    #[test]
    fn normal_client_keeps_udp_rendezvous_registration() {
        assert!(!should_use_tcp_rendezvous(
            false, false, false, false, false
        ));
        assert!(should_use_tcp_rendezvous(
            true, false, false, false, false
        ));
        assert!(should_use_tcp_rendezvous(
            false, false, true, false, false
        ));
        assert!(should_use_tcp_rendezvous(
            false, false, false, true, false
        ));
        assert!(should_use_tcp_rendezvous(
            false, false, false, false, true
        ));
    }
}

fn get_direct_port() -> i32 {
    ensure_dynamic_firewall_rule();
    let mtx = DIRECT_PORT.get_or_init(|| std::sync::Mutex::new(configured_direct_port()));
    *mtx.lock().unwrap()
}

fn sync_direct_port_from_config() {
    let configured = configured_direct_port();
    let mtx = DIRECT_PORT.get_or_init(|| std::sync::Mutex::new(configured));
    let mut port = mtx.lock().unwrap();
    if *port != configured {
        *port = configured;
    }
}

/// Mark the current port as failed (e.g. port already in use),
/// incrementing through the fixed VPS fallback range 21118-21128.
fn invalidate_direct_port() {
    if let Some(mtx) = DIRECT_PORT.get() {
        let mut port = mtx.lock().unwrap();
        let failed_port = *port;
        if *port < DEFAULT_DIRECT_PORT + 10 {
            *port += 1;
        } else {
            *port = rand::thread_rng().gen_range(20000..40000);
        }
        Config::set_option(OPTION_DIRECT_ACCESS_PORT.to_owned(), port.to_string());
        log::info!(
            "Direct port {} was unavailable, trying {}",
            failed_port,
            *port
        );
    }
}

fn reset_direct_port() {
    if let Some(mtx) = DIRECT_PORT.get() {
        let mut port = mtx.lock().unwrap();
        *port = configured_direct_port();
    }
}

pub fn ensure_direct_port() -> i32 {
    // The direct server runs in a separate process and may have re-rolled the
    // port (bind failure) and written the actual bound port back to the shared
    // config. Sync the in-process cache with the config first so callers (e.g.
    // the UI process, which then pushes the value back through IPC and can
    // otherwise overwrite the config with a stale value) never propagate a
    // stale port.
    sync_direct_port_from_config();
    get_direct_port()
}

/// Refresh a stored direct pairing with a freshly observed endpoint (IP:port).
///
/// Called whenever an authorized/direct connection confirms the peer's current
/// direct-access port, so DHCP IP changes or per-machine port randomization do
/// not leave stale endpoints that make messages look "rejected" or "offline".
/// Only LAN endpoints are updated (never relay servers), and only pairings that
/// already carry a verified fingerprint are touched; no pairings are created.
pub fn update_direct_pairing_endpoint(peer_id: &str, endpoint: &str) {
    use hbb_common::config::LocalConfig;
    const PAIRING_KEY: &str = "direct-pairings-v1";
    let raw = LocalConfig::get_option(PAIRING_KEY);
    if raw.is_empty() {
        return;
    }
    let Ok(mut pairings) = serde_json::from_str::<serde_json::Value>(&raw) else {
        return;
    };
    let Some(obj) = pairings.as_object_mut() else {
        return;
    };
    let trimmed = endpoint.trim().to_lowercase();
    let Some((ip, _port)) = trimmed.rsplit_once(':') else {
        return;
    };
    if ip.is_empty() || !crate::common::is_lan_ip(ip) {
        return;
    }
    // my_id may carry an "@rendezvous" suffix; pairings are keyed by the bare ID.
    let bare_id = peer_id.split('@').next().unwrap_or(peer_id);
    let mut target = None;
    for (key, value) in obj.iter() {
        let pid = value.get("peer_id").and_then(|v| v.as_str()).unwrap_or(key);
        let aid = value.get("account_id").and_then(|v| v.as_str());
        if pid == bare_id || aid == Some(bare_id) {
            target = Some(key.clone());
            break;
        }
    }
    let Some(key) = target else {
        return;
    };
    let Some(pairing) = obj.get_mut(&key) else {
        return;
    };
    if pairing
        .get("fingerprint")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .is_empty()
    {
        return;
    }
    let current = pairing
        .get("lan_endpoint")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if current.eq_ignore_ascii_case(&trimmed) {
        return; // unchanged: avoid needless disk writes from periodic LAN discovery
    }
    let now = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Nanos, true);
    pairing["lan_endpoint"] = serde_json::json!(trimmed);
    pairing["updated_at"] = serde_json::json!(now);
    let mut history = pairing
        .get("endpoint_history")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    history.retain(|entry| {
        entry.get("endpoint").and_then(|v| v.as_str()) != Some(trimmed.as_str())
    });
    history.insert(
        0,
        serde_json::json!({
            "endpoint": trimmed,
            "first_seen_at": now,
            "last_seen_at": now,
            "connection_count": 1,
            "secure": true,
            "stream_type": "TCP",
        }),
    );
    history.truncate(8);
    pairing["endpoint_history"] = serde_json::json!(history);
    if let Ok(out) = serde_json::to_string(&pairings) {
        LocalConfig::set_option(PAIRING_KEY.to_owned(), out);
        log::info!("Direct pairing {} endpoint refreshed to {}", bare_id, trimmed);
        #[cfg(feature = "flutter")]
        crate::flutter_ffi::push_direct_pairings_changed();
    }
}

async fn direct_server(server: ServerPtr) {
    let mut listener = None;
    let mut port = 0;
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let mut mapped_port: Option<u16> = None;
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let mut mapped_at: Option<Instant> = None;
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let mut mapping_refresh_after = Duration::from_secs(30 * 60);
    loop {
        sync_direct_port_from_config();
        let disabled = !option2bool(
            OPTION_DIRECT_SERVER,
            &Config::get_option(OPTION_DIRECT_SERVER),
        ) || option2bool("stop-service", &Config::get_option("stop-service"));
        if disabled && listener.is_none() {
            set_direct_listener_status("not-ready");
        }
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        if !disabled {
            if let (Some(current_port), Some(last_refresh)) = (mapped_port, mapped_at) {
                if elapsed_safe(last_refresh) >= mapping_refresh_after {
                    let renewed = crate::upnp::add_port_mapping(current_port);
                    Config::set_option(
                        "upnp-status".to_owned(),
                        if renewed { "ok" } else { "fail" }.to_owned(),
                    );
                    if renewed {
                        mapped_at = Some(Instant::now());
                        mapping_refresh_after = Duration::from_secs(30 * 60);
                    } else {
                        mapped_at = Some(Instant::now());
                        mapping_refresh_after = Duration::from_secs(5 * 60);
                    }
                }
            }
        }
        if !disabled && listener.is_none() {
            set_direct_listener_status("connecting");
            port = get_direct_port();
            match hbb_common::tcp::listen_any(port as _).await {
                Ok(l) => {
                    listener = Some(l);
                    if configured_direct_port() != port {
                        listener = None;
                        continue;
                    }
                    set_direct_listener_status("ready");
                    log::info!(
                        "Direct server listening on: {:?}",
                        listener.as_ref().map(|l| l.local_addr())
                    );
                    // Sync the actual port to UI option so the IP:port display stays correct
                    // even when the default port was unavailable and we fell back.
                    Config::set_option("direct-access-port".to_owned(), port.to_string());
                    #[cfg(not(any(target_os = "android", target_os = "ios")))]
                    {
                        let upnp_port = port as u16;
                        if let Some(previous_port) = mapped_port.take() {
                            if previous_port != upnp_port {
                                crate::upnp::remove_port_mapping(previous_port);
                            }
                        }
                        mapped_at = None;
                        let ret = crate::upnp::add_port_mapping(upnp_port);
                        mapped_port = Some(upnp_port);
                        mapped_at = Some(Instant::now());
                        mapping_refresh_after = if ret {
                            Duration::from_secs(30 * 60)
                        } else {
                            Duration::from_secs(5 * 60)
                        };
                        Config::set_option(
                            "upnp-status".to_owned(),
                            if ret { "ok" } else { "fail" }.to_owned(),
                        );
                        if ret {
                            log::info!(
                                "UPnP: port {} mapped successfully", port);
                        } else {
                            log::warn!(
                                "UPnP: port {} mapping failed; open the port manually if needed", port);
                        }
                    }
                    #[cfg(any(target_os = "android", target_os = "ios"))]
                    {
                        Config::set_option("upnp-status".to_owned(), "unsupported".to_owned());
                    }
                }
                Err(err) => {
                    if configured_direct_port() != port {
                        sync_direct_port_from_config();
                        continue;
                    }
                    log::error!(
                        "Failed to start direct server on port: {}, error: {}",
                        port,
                        err
                    );
                    #[cfg(not(any(target_os = "android", target_os = "ios")))]
                    invalidate_direct_port();
                    #[cfg(any(target_os = "android", target_os = "ios"))]
                    log::warn!(
                        "Mobile direct server keeps retrying port {} to avoid endpoint drift",
                        port
                    );
                    sleep(1.).await;
                }
            }
        }
        if let Some(l) = listener.as_mut() {
            if disabled || port != get_direct_port() {
                log::info!("Exit direct access listen");
                listener = None;
                set_direct_listener_status(if disabled { "not-ready" } else { "connecting" });
                #[cfg(not(any(target_os = "android", target_os = "ios")))]
                if let Some(previous_port) = mapped_port.take() {
                    crate::upnp::remove_port_mapping(previous_port);
                }
                #[cfg(not(any(target_os = "android", target_os = "ios")))]
                {
                    mapped_at = None;
                }
                Config::set_option("upnp-status".to_owned(), "disabled".to_owned());
                // Keep the next listener aligned with the configured port.
                reset_direct_port();
                continue;
            }
            if let Ok(Ok((tcp_stream, addr))) = hbb_common::timeout(1000, l.accept()).await {
                tcp_stream.set_nodelay(true).ok();
                log::info!("direct access from {}", addr);
                let local_addr = tcp_stream
                    .local_addr()
                    .unwrap_or(Config::get_any_listen_addr(true));
                let server = server.clone();
                tokio::spawn(async move {
                    allow_err!(
                        crate::server::create_tcp_connection(
                            server,
                            hbb_common::Stream::from(tcp_stream, local_addr),
                            addr,
                            true,
                            None,
                        )
                        .await
                    );
                });
            } else {
                sleep(0.1).await;
            }
        } else {
            sleep(1.).await;
        }
    }
}

enum Sink<'a> {
    Framed(&'a mut FramedSocket, &'a TargetAddr<'a>),
    Stream(&'a mut Stream),
}

impl Sink<'_> {
    async fn send(self, msg: &Message) -> ResultType<()> {
        match self {
            Sink::Framed(socket, addr) => socket.send(msg, addr.to_owned()).await,
            Sink::Stream(stream) => stream.send(msg).await,
        }
    }
}

async fn start_ipv6(
    peer_addr_v6: SocketAddr,
    peer_addr_v4: SocketAddr,
    server: ServerPtr,
    control_permissions: Option<ControlPermissions>,
) -> bytes::Bytes {
    crate::test_ipv6().await;
    if let Some((socket, local_addr_v6)) = crate::get_ipv6_socket().await {
        let server = server.clone();
        tokio::spawn(async move {
            allow_err!(
                udp_nat_listen(
                    socket.clone(),
                    peer_addr_v6,
                    peer_addr_v4,
                    server,
                    control_permissions
                )
                .await
            );
        });
        return local_addr_v6;
    }
    Default::default()
}

async fn udp_nat_listen(
    socket: Arc<tokio::net::UdpSocket>,
    peer_addr: SocketAddr,
    peer_addr_v4: SocketAddr,
    server: ServerPtr,
    control_permissions: Option<ControlPermissions>,
) -> ResultType<()> {
    let tm = Instant::now();
    let socket_cloned = socket.clone();
    let func = async {
        socket.connect(peer_addr).await?;
        let res = crate::punch_udp(socket.clone(), true).await?;
        let stream = crate::kcp_stream::KcpStream::accept(
            socket,
            Duration::from_millis(CONNECT_TIMEOUT as _),
            res,
        )
        .await?;
        crate::server::create_tcp_connection(
            server,
            stream.1,
            peer_addr_v4,
            true,
            control_permissions,
        )
        .await?;
        Ok(())
    };
    func.await.map_err(|e: anyhow::Error| {
        anyhow::anyhow!(
            "Stop listening on {:?} for remote {peer_addr} with KCP, {:?} elapsed: {e}",
            socket_cloned.local_addr(),
            elapsed_safe(tm)
        )
    })?;
    Ok(())
}

// When config is not yet synced from root, register_pk may have already been sent with a new generated pk.
// After config sync completes, the pk may change. This struct detects pk changes and triggers
// a re-registration by setting key_confirmed to false.
// NOTE:
// This only corrects PK registration for the current ID. If root uses a non-default mac-generated ID,
// this does not resolve the multi-ID issue by itself.
pub struct CheckIfResendPk {
    pk: Option<Vec<u8>>,
}
impl CheckIfResendPk {
    pub fn new() -> Self {
        Self {
            pk: Config::get_cached_pk(),
        }
    }
}
impl Drop for CheckIfResendPk {
    fn drop(&mut self) {
        if SENT_REGISTER_PK.load(Ordering::SeqCst) && Config::get_cached_pk() != self.pk {
            Config::set_key_confirmed(false);
            log::info!("Set key_confirmed to false due to pk changed, will resend register_pk");
        }
    }
}
