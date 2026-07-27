use super::*;
use crate::common::SimpleCallOnReturn;
#[cfg(target_os = "linux")]
use crate::platform::linux::is_x11;
#[cfg(windows)]
use crate::virtual_display_manager;
#[cfg(windows)]
use hbb_common::get_version_number;
use hbb_common::protobuf::MessageField;
use scrap::Display;
use std::sync::atomic::{AtomicBool, Ordering};
#[cfg(windows)]
use std::time::{Duration, Instant};

// https://github.com/luoda/luoda/discussions/6042, avoiding dbus call

pub const NAME: &'static str = "display";

#[cfg(windows)]
const DUMMY_DISPLAY_SIDE_MAX_SIZE: usize = 1024;
#[cfg(windows)]
const HEADLESS_DISPLAY_WAIT_TIMEOUT: Duration = Duration::from_secs(8);
#[cfg(windows)]
const HEADLESS_DISPLAY_POLL_INTERVAL: Duration = Duration::from_millis(200);

struct ChangedResolution {
    original: (i32, i32),
    changed: (i32, i32),
}

lazy_static::lazy_static! {
    static ref IS_CAPTURER_MAGNIFIER_SUPPORTED: bool = is_capturer_mag_supported();
    static ref CHANGED_RESOLUTIONS: Arc<RwLock<HashMap<String, ChangedResolution>>> = Default::default();
    // Initial primary display index.
    // It should not be updated when displays changed.
    pub static ref PRIMARY_DISPLAY_IDX: usize = get_primary();
    static ref SYNC_DISPLAYS: Arc<Mutex<SyncDisplaysInfo>> = Default::default();
}

// https://github.com/luoda/luoda/pull/8537
static TEMP_IGNORE_DISPLAYS_CHANGED: AtomicBool = AtomicBool::new(false);
#[cfg(windows)]
static PREFER_VIRTUAL_DISPLAY: AtomicBool = AtomicBool::new(false);

#[cfg(windows)]
fn filter_and_order_displays(displays: &mut Vec<Display>) {
    displays.retain(|display| display.is_online());
    if !PREFER_VIRTUAL_DISPLAY.load(Ordering::Relaxed) {
        return;
    }
    if let Some(index) = displays
        .iter()
        .position(|display| virtual_display_manager::is_virtual_display(&display.name()))
    {
        displays.swap(0, index);
    }
}

#[cfg(windows)]
pub(crate) fn prefer_virtual_display() {
    PREFER_VIRTUAL_DISPLAY.store(true, Ordering::Relaxed);
}

#[derive(Default)]
struct SyncDisplaysInfo {
    displays: Vec<DisplayInfo>,
    is_synced: bool,
}

impl SyncDisplaysInfo {
    fn check_changed(&mut self, displays: Vec<DisplayInfo>) {
        if self.displays.len() != displays.len() {
            self.displays = displays;
            if !TEMP_IGNORE_DISPLAYS_CHANGED.load(Ordering::Relaxed) {
                self.is_synced = false;
            }
            return;
        }
        for (i, d) in displays.iter().enumerate() {
            if d != &self.displays[i] {
                self.displays = displays;
                if !TEMP_IGNORE_DISPLAYS_CHANGED.load(Ordering::Relaxed) {
                    self.is_synced = false;
                }
                return;
            }
        }
    }

    fn get_update_sync_displays(&mut self) -> Option<Vec<DisplayInfo>> {
        if self.is_synced {
            return None;
        }
        self.is_synced = true;
        Some(self.displays.clone())
    }
}

pub fn temp_ignore_displays_changed() -> SimpleCallOnReturn {
    TEMP_IGNORE_DISPLAYS_CHANGED.store(true, std::sync::atomic::Ordering::Relaxed);
    SimpleCallOnReturn {
        b: true,
        f: Box::new(move || {
            // Wait for a while to make sure check_display_changed() is called
            // after video service has sending its `SwitchDisplay` message(`try_broadcast_display_changed()`).
            std::thread::sleep(Duration::from_millis(1000));
            TEMP_IGNORE_DISPLAYS_CHANGED.store(false, Ordering::Relaxed);
            // Trigger the display changed message.
            SYNC_DISPLAYS.lock().unwrap().is_synced = false;
        }),
    }
}

// This function is really useful, though a duplicate check if display changed.
// The video server will then send the following messages to the client:
//  1. the supported resolutions of the {idx} display
//  2. the switch resolution message, so that the client can record the custom resolution.
pub(super) fn check_display_changed(
    ndisplay: usize,
    idx: usize,
    (x, y, w, h): (i32, i32, usize, usize),
) -> Option<DisplayInfo> {
    #[cfg(target_os = "linux")]
    {
        // wayland do not support changing display for now
        if !is_x11() {
            return None;
        }
    }

    let lock = SYNC_DISPLAYS.lock().unwrap();
    // If plugging out a monitor && lock.displays.get(idx) is None.
    //  1. The client version < 1.2.4. The client side has to reconnect.
    //  2. The client version > 1.2.4, The client side can handle the case because sync peer info message will be sent.
    // But it is acceptable to for the user to reconnect manually, because the monitor is unplugged.
    let d = lock.displays.get(idx)?;
    if ndisplay != lock.displays.len() {
        return Some(d.clone());
    }
    if !(d.x == x && d.y == y && d.width == w as i32 && d.height == h as i32) {
        Some(d.clone())
    } else {
        None
    }
}

#[inline]
pub fn set_last_changed_resolution(display_name: &str, original: (i32, i32), changed: (i32, i32)) {
    let mut lock = CHANGED_RESOLUTIONS.write().unwrap();
    match lock.get_mut(display_name) {
        Some(res) => res.changed = changed,
        None => {
            lock.insert(
                display_name.to_owned(),
                ChangedResolution { original, changed },
            );
        }
    }
}

#[inline]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn restore_resolutions() {
    for (name, res) in CHANGED_RESOLUTIONS.read().unwrap().iter() {
        let (w, h) = res.original;
        log::info!("Restore resolution of display '{}' to ({}, {})", name, w, h);
        if let Err(e) = crate::platform::change_resolution(name, w as _, h as _) {
            log::error!(
                "Failed to restore resolution of display '{}' to ({},{}): {}",
                name,
                w,
                h,
                e
            );
        }
    }
    // Can be cleared because restore resolutions is called when there is no client connected.
    CHANGED_RESOLUTIONS.write().unwrap().clear();
}

#[inline]
fn is_capturer_mag_supported() -> bool {
    #[cfg(windows)]
    return scrap::CapturerMag::is_supported();
    #[cfg(not(windows))]
    false
}

#[inline]
pub fn capture_cursor_embedded() -> bool {
    scrap::is_cursor_embedded()
}

#[inline]
#[cfg(windows)]
pub fn is_privacy_mode_mag_supported() -> bool {
    return *IS_CAPTURER_MAGNIFIER_SUPPORTED
        && get_version_number(&crate::VERSION) > get_version_number("1.1.9");
}

pub fn new() -> GenericService {
    let svc = EmptyExtraFieldService::new(NAME.to_owned(), true);
    GenericService::run(&svc.clone(), run);
    svc.sp
}

fn displays_to_msg(displays: Vec<DisplayInfo>) -> Message {
    let mut pi = PeerInfo {
        ..Default::default()
    };
    pi.displays = displays.clone();

    #[cfg(windows)]
    if crate::platform::is_installed() {
        let m = crate::virtual_display_manager::get_platform_additions();
        pi.platform_additions = serde_json::to_string(&m).unwrap_or_default();
    }

    // current_display should not be used in server.
    // It is set to 0 for compatibility with old clients.
    pi.current_display = 0;
    let mut msg_out = Message::new();
    msg_out.set_peer_info(pi);
    msg_out
}

fn check_get_displays_changed_msg() -> Option<Message> {
    #[cfg(target_os = "linux")]
    {
        if !is_x11() {
            return get_displays_msg();
        }
    }
    check_update_displays(&try_get_displays().ok()?);
    get_displays_msg()
}

pub fn check_displays_changed() -> ResultType<()> {
    #[cfg(target_os = "linux")]
    {
        // Currently, wayland need to call wayland::clear() before call Display::all(), otherwise it will cause
        // block, or even crash here, https://github.com/luoda/luoda/blob/0bb4d43e9ea9d9dfb9c46c8d27d1a97cd0ad6bea/libs/scrap/src/wayland/pipewire.rs#L235
        if !is_x11() {
            return Ok(());
        }
    }
    check_update_displays(&try_get_displays()?);
    Ok(())
}

fn get_displays_msg() -> Option<Message> {
    let displays = SYNC_DISPLAYS.lock().unwrap().get_update_sync_displays()?;
    Some(displays_to_msg(displays))
}

fn run(sp: EmptyExtraFieldService) -> ResultType<()> {
    while sp.ok() {
        sp.snapshot(|sps| {
            if !TEMP_IGNORE_DISPLAYS_CHANGED.load(Ordering::Relaxed) {
                if sps.has_subscribes() {
                    SYNC_DISPLAYS.lock().unwrap().is_synced = false;
                    bail!("new subscriber");
                }
            }
            Ok(())
        })?;

        if let Some(msg_out) = check_get_displays_changed_msg() {
            sp.send(msg_out);
            log::info!("Displays changed");
        }
        std::thread::sleep(Duration::from_millis(300));
    }

    Ok(())
}

#[inline]
pub(super) fn get_original_resolution(
    display_name: &str,
    w: usize,
    h: usize,
) -> MessageField<Resolution> {
    #[cfg(windows)]
    let is_luoda_virtual_display =
        crate::virtual_display_manager::luoda_idd::is_virtual_display(&display_name);
    #[cfg(not(windows))]
    let is_luoda_virtual_display = false;
    Some(if is_luoda_virtual_display {
        Resolution {
            width: 0,
            height: 0,
            ..Default::default()
        }
    } else {
        let changed_resolutions = CHANGED_RESOLUTIONS.write().unwrap();
        let (width, height) = match changed_resolutions.get(display_name) {
            Some(res) => {
                res.original
                /*
                The resolution change may not happen immediately, `changed` has been updated,
                but the actual resolution is old, it will be mistaken for a third-party change.
                if res.changed.0 != w as i32 || res.changed.1 != h as i32 {
                    // If the resolution is changed by third process, remove the record in changed_resolutions.
                    changed_resolutions.remove(display_name);
                    (w as _, h as _)
                } else {
                    res.original
                }
                */
            }
            None => (w as _, h as _),
        };
        Resolution {
            width,
            height,
            ..Default::default()
        }
    })
    .into()
}

pub(super) fn get_sync_displays() -> Vec<DisplayInfo> {
    SYNC_DISPLAYS.lock().unwrap().displays.clone()
}

pub(super) fn get_display_info(idx: usize) -> Option<DisplayInfo> {
    SYNC_DISPLAYS.lock().unwrap().displays.get(idx).cloned()
}

// Display to DisplayInfo
// The DisplayInfo is be sent to the peer.
pub(super) fn check_update_displays(all: &Vec<Display>) {
    // For compatibility: if only one display, scale remains 1.0 and we use the physical size for `uinput`.
    // If there are multiple displays, we use the logical size for `uinput` by setting scale to d.scale().
    #[cfg(target_os = "linux")]
    let use_logical_scale = !is_x11()
        && crate::is_server()
        && scrap::wayland::display::get_displays().displays.len() > 1;
    let displays = all
        .iter()
        .map(|d| {
            let display_name = d.name();
            #[allow(unused_assignments)]
            #[allow(unused_mut)]
            let mut scale = 1.0;
            #[cfg(target_os = "macos")]
            {
                scale = d.scale();
            }
            #[cfg(target_os = "linux")]
            {
                if use_logical_scale {
                    scale = d.scale();
                }
            }
            // NOTE: For Windows we intentionally keep scale = 1.0 (matching
            // upstream RustDesk). The controlled side reports physical pixel
            // dimensions and the client maps mouse coordinates in that physical
            // space; enigo on Windows consumes those physical coordinates
            // directly. Reporting the real DPI scale here (and/or rescaling
            // injected mouse events) shifts the cursor away from the click
            // point, so it must NOT be done.
            let original_resolution = get_original_resolution(
                &display_name,
                ((d.width() as f64) / scale).round() as usize,
                (d.height() as f64 / scale).round() as usize,
            );
            DisplayInfo {
                x: d.origin().0 as _,
                y: d.origin().1 as _,
                width: d.width() as _,
                height: d.height() as _,
                name: display_name,
                online: d.is_online(),
                cursor_embedded: false,
                original_resolution,
                scale,
                ..Default::default()
            }
        })
        .collect::<Vec<DisplayInfo>>();
    SYNC_DISPLAYS.lock().unwrap().check_changed(displays);
}

pub fn is_inited_msg() -> Option<Message> {
    #[cfg(target_os = "linux")]
    if !is_x11() {
        return super::wayland::is_inited();
    }
    None
}

pub async fn update_get_sync_displays_on_login() -> ResultType<Vec<DisplayInfo>> {
    #[cfg(target_os = "linux")]
    {
        if !is_x11() {
            return super::wayland::get_displays().await;
        }
    }
    #[cfg(not(windows))]
    let displays = display_service::try_get_displays();
    #[cfg(windows)]
    let displays = display_service::try_get_displays_add_amyuni_headless();
    check_update_displays(&displays?);
    Ok(SYNC_DISPLAYS.lock().unwrap().displays.clone())
}

#[inline]
pub fn get_primary() -> usize {
    #[cfg(target_os = "linux")]
    {
        if !is_x11() {
            return match super::wayland::get_primary() {
                Ok(n) => n,
                Err(_) => 0,
            };
        }
    }

    try_get_displays().map(|d| get_primary_2(&d)).unwrap_or(0)
}

#[inline]
pub fn get_primary_2(all: &Vec<Display>) -> usize {
    all.iter().position(|d| d.is_primary()).unwrap_or(0)
}

#[inline]
#[cfg(windows)]
pub(crate) fn no_displays(displays: &Vec<Display>) -> bool {
    let display_len = displays.len();
    if display_len == 0 {
        true
    } else if display_len == 1 {
        let display = &displays[0];
        if display.width() > DUMMY_DISPLAY_SIDE_MAX_SIZE
            || display.height() > DUMMY_DISPLAY_SIDE_MAX_SIZE
        {
            return false;
        }
        let any_real = crate::platform::resolutions(&display.name())
            .iter()
            .any(|r| {
                (r.height as usize) > DUMMY_DISPLAY_SIDE_MAX_SIZE
                    || (r.width as usize) > DUMMY_DISPLAY_SIDE_MAX_SIZE
            });
        !any_real
    } else {
        false
    }
}

#[inline]
#[cfg(not(windows))]
pub fn try_get_displays() -> ResultType<Vec<Display>> {
    // 无物理显示器时不报错，返回空列表让连接继续
    // （例如 headless server 只需聊天/文件传输，不需要实际屏幕捕获）
    match Display::all() {
        Ok(d) => Ok(d),
        Err(_) => Ok(Vec::new()),
    }
}

#[inline]
#[cfg(windows)]
pub fn try_get_displays() -> ResultType<Vec<Display>> {
    try_get_displays_(false)
}

// We can't get full control of the virtual display if we use amyuni idd.
// If we add a virtual display, we cannot remove it automatically.
// So when using amyuni idd, we only add a virtual display for headless if it is required.
// eg. when the client is connecting.
#[inline]
#[cfg(windows)]
pub fn try_get_displays_add_amyuni_headless() -> ResultType<Vec<Display>> {
    try_get_displays_(true)
}

#[cfg(windows)]
fn wait_for_headless_display() -> ResultType<Vec<Display>> {
    let started = Instant::now();
    // Give the virtual display driver more time on first boot / after RDP disconnect.
    let timeout = if crate::platform::windows::is_win_server() {
        Duration::from_secs(16)
    } else {
        HEADLESS_DISPLAY_WAIT_TIMEOUT
    };
    loop {
        match Display::all() {
            Ok(mut displays) => {
                filter_and_order_displays(&mut displays);
                if displays
                    .iter()
                    .any(|display| virtual_display_manager::is_virtual_display(&display.name()))
                {
                    return Ok(displays);
                }
                // If there are real (non-virtual) displays, those are fine too.
                if !displays.is_empty() && started.elapsed() >= timeout / 2 {
                    log::warn!(
                        "virtual display not found, but {} real display(s) available; using those",
                        displays.len()
                    );
                    return Ok(displays);
                }
                if started.elapsed() >= timeout {
                    // Last resort: return whatever we have so the video service
                    // can attempt its own recovery path.
                    if !displays.is_empty() {
                        log::warn!("headless display timeout, returning {} display(s)", displays.len());
                        return Ok(displays);
                    }
                    bail!("virtual display did not enumerate before timeout");
                }
            }
            Err(error) => {
                if started.elapsed() >= timeout {
                    return Err(error.into());
                }
                log::debug!("waiting for headless display: {error}");
            }
        }
        std::thread::sleep(HEADLESS_DISPLAY_POLL_INTERVAL);
    }
}

#[cfg(windows)]
pub(crate) fn plug_in_headless_and_wait() -> ResultType<Vec<Display>> {
    if !virtual_display_manager::has_headless_display() {
        if let Err(error) = virtual_display_manager::plug_in_headless() {
            log::error!("plug in headless failed {error}");
            return Err(error);
        }
    }
    wait_for_headless_display()
}

#[cfg(windows)]
pub(crate) fn prepare_windows_server_headless_display() -> ResultType<()> {
    if !virtual_display_manager::is_virtual_display_supported() {
        return Ok(());
    }
    // If a headless display already exists, no action needed.
    if virtual_display_manager::has_headless_display() {
        log::debug!("headless display already present");
        return Ok(());
    }
    match plug_in_headless_and_wait() {
        Ok(_) => Ok(()),
        Err(e) => {
            // Even if the virtual display creation fails, we return Ok
            // on Windows Server portable mode so the video service can still
            // start and try its own recovery later.
            let is_portable =
                std::env::var_os(crate::common::PORTABLE_APPNAME_RUNTIME_ENV_KEY).is_some();
            if crate::platform::windows::is_win_server() || is_portable {
                log::warn!(
                    "headless display preparation failed (will retry on capture): {e}"
                );
                Ok(())
            } else {
                Err(e)
            }
        }
    }
}

#[inline]
#[cfg(windows)]
pub fn try_get_displays_(add_amyuni_headless: bool) -> ResultType<Vec<Display>> {
    let mut displays = Display::all()?;
    filter_and_order_displays(&mut displays);

    // Portable VPS hosts also need the bundled virtual display driver after
    // an RDP session disconnects, so installation state must not gate this.
    if !virtual_display_manager::is_virtual_display_supported() {
        return Ok(displays);
    }

    // Enable headless virtual display when
    // 1. `amyuni` idd is not used.
    // 2. `amyuni` idd is used and `add_amyuni_headless` is true.
    if virtual_display_manager::is_amyuni_idd() && !add_amyuni_headless {
        return Ok(displays);
    }

    // The following code causes a bug.
    // The virtual display cannot be added when there's no session(eg. when exiting from RDP).
    // Because `crate::platform::desktop_changed()` always returns true at that time.
    //
    // The code only solves a rare case:
    // 1. The control side is connecting.
    // 2. The windows session is switching, no displays are detected, but they're there.
    // Then the controlled side plugs in a virtual display for "headless".
    //
    // No need to do the following check. But the code is kept here for marking the issue.
    // If there're someones reporting the issue, we may add a better check by waiting for a while. (switching session).
    // But I don't think it's good to add the timeout check without any issue.
    //
    // If is switching session, no displays may be detected.
    // if displays.is_empty() && crate::platform::desktop_changed() {
    //     return Ok(displays);
    // }

    let no_displays_v = no_displays(&displays);
    if no_displays_v {
        log::debug!("no displays, create virtual display");
        match plug_in_headless_and_wait() {
            Ok(d) => displays = d,
            Err(e) => {
                log::error!("failed to create virtual display: {e}");
                // On portable VPS, try one more time with a longer wait.
                let is_portable = std::env::var_os(
                    crate::common::PORTABLE_APPNAME_RUNTIME_ENV_KEY,
                )
                .is_some();
                if is_portable || crate::platform::windows::is_win_server() {
                    std::thread::sleep(Duration::from_secs(3));
                    if let Ok(d) = Display::all() {
                        let mut d = d;
                        filter_and_order_displays(&mut d);
                        if !d.is_empty() {
                            displays = d;
                        }
                    }
                }
            }
        }
    }
    Ok(displays)
}
