use crate::client::translate;
#[cfg(windows)]
use crate::ipc::Data;
#[cfg(windows)]
use hbb_common::tokio;
use hbb_common::{allow_err, log};
use std::sync::{Arc, Mutex};
#[cfg(windows)]
use std::time::Duration;

pub fn start_tray() {
    log::info!("Tray started");
    if crate::ui_interface::get_builtin_option(hbb_common::config::keys::OPTION_HIDE_TRAY) == "Y" {
        #[cfg(not(target_os = "macos"))]
        {
            return;
        }
    }

    // Only one tray icon per user session, even when the same build is
    // launched from two different folders or an older build is still
    // resident (its --tray child is not matched by check_process because
    // that compares executable paths). Without the mutex, users see two
    // DotChat icons in the tray.
    #[cfg(target_os = "windows")]
    if !acquire_tray_icon_lock() {
        log::warn!(
            "another {} tray icon already exists; skipping duplicate",
            crate::get_app_name()
        );
        return;
    }

    #[cfg(target_os = "linux")]
    crate::server::check_zombie();

    allow_err!(make_tray());
}

/// Windows: hold a named mutex while this process owns the tray icon. If the
/// mutex already exists, another live process owns the tray icon and this
/// process must not create a second one.
#[cfg(target_os = "windows")]
fn acquire_tray_icon_lock() -> bool {
    use std::hash::{Hash, Hasher};
    use windows::core::PCWSTR;
    use windows::Win32::Foundation::{CloseHandle, GetLastError, ERROR_ALREADY_EXISTS};
    use windows::Win32::System::Threading::CreateMutexW;

    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    crate::get_app_name().hash(&mut hasher);
    let name = format!("LUODA_TrayIcon_{:016x}", hasher.finish());
    let wide: Vec<u16> = name.encode_utf16().chain(std::iter::once(0)).collect();
    let handle = unsafe { CreateMutexW(None, false, PCWSTR(wide.as_ptr())) };
    let Ok(handle) = handle else {
        // Mutex creation failed; do not block the tray on that.
        log::warn!("failed to create tray mutex {name}; continuing");
        return true;
    };
    if unsafe { GetLastError() } == ERROR_ALREADY_EXISTS {
        let _ = unsafe { CloseHandle(handle) };
        return false;
    }
    // Keep the mutex handle alive for the whole process lifetime.
    std::mem::forget(handle);
    true
}

fn make_tray() -> hbb_common::ResultType<()> {
    // https://github.com/tauri-apps/tray-icon/blob/dev/examples/tao.rs
    use hbb_common::anyhow::Context;
    use tao::event_loop::{ControlFlow, EventLoopBuilder};
    use tray_icon::{
        menu::{Menu, MenuEvent, MenuItem},
        TrayIcon, TrayIconBuilder, TrayIconEvent as TrayEvent,
    };
    let icon;
    #[cfg(target_os = "macos")]
    {
        icon = include_bytes!("../res/mac-tray-dark-x2.png"); // use as template, so color is not important
    }
    #[cfg(target_os = "windows")]
    {
        icon = include_bytes!("../res/tray-icon.png");
    }
    #[cfg(all(not(target_os = "macos"), not(target_os = "windows")))]
    {
        icon = include_bytes!("../res/tray-icon.ico");
    }

    let (icon_rgba, icon_width, icon_height) = {
        // Windows 直接加载品牌 32×32 PNG，避免 ICO 解码选中旧尺寸图层。
        #[cfg(windows)]
        let image = None;
        #[cfg(not(windows))]
        let image = load_icon_from_asset();
        let image = image.unwrap_or(image::load_from_memory(icon).context("Failed to open icon path")?)
            .into_rgba8();
        let (width, height) = image.dimensions();
        let rgba = image.into_raw();
        (rgba, width, height)
    };
    let icon = tray_icon::Icon::from_rgba(icon_rgba, icon_width, icon_height)
        .context("Failed to open icon")?;

    #[cfg(windows)]
    let mut event_loop = {
        use tao::platform::windows::EventLoopBuilderExtWindows;
        EventLoopBuilder::new().with_any_thread(true).build()
    };
    #[cfg(not(windows))]
    let mut event_loop = EventLoopBuilder::new().build();

    let tray_menu = Menu::new();
    let hide_stop_service = crate::ui_interface::get_builtin_option(
        hbb_common::config::keys::OPTION_HIDE_STOP_SERVICE,
    ) == "Y";
    // The tray icon is only shown when the service is running, so we don't need to check
    // the `stop-service` option here.
    let disconnect_i = if !hide_stop_service {
        Some(MenuItem::new(translate("Stop service".to_owned()), true, None))
    } else {
        None
    };
    let exit_i = MenuItem::new(translate("Exit".to_owned()), true, None);
    let open_i = MenuItem::new(translate("Open".to_owned()), true, None);
    if let Some(disconnect_i) = &disconnect_i {
        tray_menu.append_items(&[&open_i, disconnect_i, &exit_i]).ok();
    } else {
        tray_menu.append_items(&[&open_i, &exit_i]).ok();
    }
    let tooltip = |count: usize| {
        if count == 0 {
            format!(
                "{} {}",
                crate::get_display_name(),
                translate("Service is running".to_owned()),
            )
        } else {
            format!(
                "{} - {}\n{}",
                crate::get_display_name(),
                translate("Ready".to_owned()),
                translate("{".to_string() + &format!("{count}") + "} sessions"),
            )
        }
    };
    let mut _tray_icon: Arc<Mutex<Option<TrayIcon>>> = Default::default();

    let menu_channel = MenuEvent::receiver();
    let tray_channel = TrayEvent::receiver();
    #[cfg(windows)]
    let (ipc_sender, ipc_receiver) = std::sync::mpsc::channel::<Data>();

    let open_func = move || {
        if cfg!(not(feature = "flutter")) {
            crate::run_me::<&str>(vec![]).ok();
            return;
        }
        #[cfg(target_os = "macos")]
        crate::platform::macos::handle_application_should_open_untitled_file();
        #[cfg(target_os = "windows")]
        {
            // Do not use "start uni link" way, it may not work on some Windows, and pop out error
            // dialog, I found on one user's desktop, but no idea why, Windows is shit.
            // Use `run_me` instead.
            // `allow_multiple_instances` in `flutter/windows/runner/main.cpp` allows only one instance without args.
            crate::run_me::<&str>(vec![]).ok();
        }
        #[cfg(target_os = "linux")]
        {
            // Do not use "xdg-open", it won't read the config.
            if crate::dbus::invoke_new_connection(crate::get_uri_prefix()).is_err() {
                if let Ok(task) = crate::run_me::<&str>(vec![]) {
                    crate::server::CHILD_PROCESS.lock().unwrap().push(task);
                }
            }
        }
    };

    #[cfg(windows)]
    std::thread::spawn(move || {
        start_query_session_count(ipc_sender.clone());
    });

    // 双击托盘图标：若主窗口可见则最小化到托盘（隐藏），否则恢复显示。
    // 主窗口是 Flutter 原生窗口，类名固定 FLUTTER_RUNNER_WIN32_WINDOW，
    // 标题为应用名（main.cpp 用同一对参数 FindWindowW 查找）。
    #[cfg(target_os = "windows")]
    fn toggle_main_window<F: Fn()>(open: &F) {
        use windows::core::PCWSTR;
        use windows::Win32::UI::WindowsAndMessaging::{
            FindWindowW, IsWindowVisible, SetForegroundWindow, ShowWindow, SW_HIDE, SW_SHOW,
        };
        let class_name = crate::platform::wide_string(
            crate::platform::FLUTTER_RUNNER_WIN32_WINDOW_CLASS,
        );
        let window_name = crate::platform::wide_string(&crate::get_app_name());
        let window = unsafe {
            FindWindowW(
                PCWSTR(class_name.as_ptr()),
                PCWSTR(window_name.as_ptr()),
            )
        };
        let Ok(window) = window else {
            log::warn!("FindWindowW failed in toggle_main_window");
            return;
        };
        if window.0.is_null() {
            // 主窗口不存在（如已被关闭或未启动）：直接打开。
            open();
            return;
        }
        if unsafe { IsWindowVisible(window) }.as_bool() {
            // 可见 -> 最小化到托盘（隐藏窗口，托盘图标保持活动）。
            unsafe { ShowWindow(window, SW_HIDE) };
        } else {
            // 已隐藏 -> 恢复显示并置前。
            unsafe {
                ShowWindow(window, SW_SHOW);
                SetForegroundWindow(window);
            }
        }
    }
    // 单击/双击区分：单击（打开窗口）延迟到双击窗口期过后再执行；
    // 双击（切换显示/最小化到托盘）立即执行。Windows 双击事件流是
    // Click(down/up) -> DoubleClick -> Click(up)，若不延迟单击，双击的
    // 第一击就会被当作单击直接打开窗口，再被 DoubleClick 隐藏，体验错乱。
    #[cfg(windows)]
    let mut last_click = std::time::Instant::now();
    #[cfg(windows)]
    let mut pending_single_click = false;
    #[cfg(windows)]
    let mut rebuild_count: u32 = 0;
    #[cfg(target_os = "macos")]
    {
        use tao::platform::macos::EventLoopExtMacOS;
        event_loop.set_activation_policy(tao::platform::macos::ActivationPolicy::Accessory);
    }
    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::WaitUntil(
            std::time::Instant::now() + std::time::Duration::from_millis(100),
        );

        if let tao::event::Event::NewEvents(tao::event::StartCause::Init) = event {
            // for fixing https://github.com/luoda/luoda/discussions/10210#discussioncomment-14600745
            // so we start tray, but not to show it
            if crate::ui_interface::get_builtin_option(hbb_common::config::keys::OPTION_HIDE_TRAY) == "Y" {
                return;
            }
            // We create the icon once the event loop is actually running
            // to prevent issues like https://github.com/tauri-apps/tray-icon/issues/90
            let tray = TrayIconBuilder::new()
                .with_menu(Box::new(tray_menu.clone()))
                .with_menu_on_right_click(true)
                .with_tooltip(tooltip(0))
                .with_icon(icon.clone())
                // icon_as_template 仅在 macOS 生效；Windows 上设 true 会被系统当模板反色，叠加缩放导致更糊
                .with_icon_as_template(cfg!(target_os = "macos"))
                .build();
            match tray {
                Ok(tray) => _tray_icon = Arc::new(Mutex::new(Some(tray))),
                Err(err) => {
                    log::error!("Failed to create tray icon: {}", err);
                }
            };

            // We have to request a redraw here to have the icon actually show up.
            // Tao only exposes a redraw method on the Window so we use core-foundation directly.
            #[cfg(target_os = "macos")]
            unsafe {
                use core_foundation::runloop::{CFRunLoopGetMain, CFRunLoopWakeUp};

                let rl = CFRunLoopGetMain();
                CFRunLoopWakeUp(rl);
            }
        }

        if let Ok(event) = menu_channel.try_recv() {
            if event.id == exit_i.id() {
                // 先停止后台服务，防止任务栏残留进程
                crate::ipc::set_option("stop-service", "Y");
                std::thread::sleep(std::time::Duration::from_millis(500));

                // 停止Windows服务（如已安装），确保服务进程退出
                #[cfg(target_os = "windows")]
                {
                    use std::os::windows::process::CommandExt;
                    let app_name = crate::get_app_name();
                    log::info!("Tray exit: stopping Windows service '{}' with sc stop", app_name);
                    let _ = std::process::Command::new("sc")
                        .args(["stop", &app_name])
                        .creation_flags(0x08000000)
                        .output();
                    std::thread::sleep(std::time::Duration::from_millis(500));
                }

                // 移除stop-service标志，让下次启动时自动连接
                // 直接写入本地配置即可（无需走IPC），仅移除stop-service这一项
                // ⚠️ 注意：不要调用 set_options(HashMap::new())，那会清空所有已保存的配置！
                hbb_common::config::Config::set_option("stop-service".to_string(), "".to_string());
                // Kill main GUI process(es) using taskkill (much faster than PowerShell).
                #[cfg(target_os = "windows")]
                {
                    use std::os::windows::process::CommandExt;
                    let exe_name = std::env::current_exe()
                        .ok()
                        .and_then(|p| p.file_stem().map(|n| n.to_string_lossy().into_owned()))
                        .unwrap_or_else(|| "luoda".to_owned());
                    log::info!("Tray exit: killing GUI with: taskkill /F /FI PID ne {} /IM {}.exe",
                        std::process::id(), exe_name);
                    let _ = std::process::Command::new("taskkill")
                        .args(["/f", "/im", &format!("{}.exe", exe_name), "/fi", &format!("PID ne {}", std::process::id())])
                        .creation_flags(0x08000000)
                        .output();
                    // 补杀可能残留的服务/命名进程
                    for stray in &["service.exe", "luoda_svc.exe", "naming.exe"] {
                        let _ = std::process::Command::new("taskkill")
                            .args(["/f", "/im", stray])
                            .creation_flags(0x08000000)
                            .output();
                    }
                }
                #[cfg(not(target_os = "windows"))]
                {
                    let exe = std::env::current_exe().unwrap_or_default();
                    let exe_name = exe.file_name().unwrap_or_default().to_string_lossy();
                    let _ = std::process::Command::new("pkill")
                        .arg("-f")
                        .arg(&*exe_name)
                        .output();
                }
                // 手动析构托盘图标，确保Windows通知区域图标被清除
                // 注意：exit(0)不会运行Drop析构函数，必须显式清理
                if let Ok(mut guard) = _tray_icon.lock() {
                    *guard = None;
                }
                std::process::exit(0);
            } else if event.id == open_i.id() {
                open_func();
            } else if let Some(disconnect_i) = &disconnect_i {
                if event.id == disconnect_i.id() {
                    // Set stop-service option so mediator actually stops accepting connections,
                    // then restart to apply the change.
                    // Must use IPC here because the tray runs as a separate process on Windows.
                    // Config::set_option only updates the local in-memory config; IPC sends
                    // the option to the server process where CheckIfRestart detects the change
                    // and calls RendezvousMediator::restart() automatically.
                    crate::ipc::set_option("stop-service", "Y");
                    std::thread::sleep(std::time::Duration::from_millis(200));
                    crate::rendezvous_mediator::RendezvousMediator::restart();
                }
            }
        }

        // 双击窗口期已过仍未收到 DoubleClick：把挂起的单击当作真正的单击执行。
        #[cfg(target_os = "windows")]
        if pending_single_click
            && last_click.elapsed()
                >= std::time::Duration::from_millis(
                    crate::platform::get_double_click_time() as u64,
                )
        {
            pending_single_click = false;
            open_func();
        }

        if let Ok(_event) = tray_channel.try_recv() {
            #[cfg(target_os = "windows")]
            match _event {
                TrayEvent::Click {
                    button,
                    button_state,
                    ..
                } => {
                    if button == tray_icon::MouseButton::Left
                        && button_state == tray_icon::MouseButtonState::Up
                    {
                        // 双击的第二击 up 会紧跟 DoubleClick 到达；此时刚执行过
                        // 切换，若再挂起一个单击会在一会儿后把窗口又打开/隐藏一次。
                        // 因此 DoubleClick 到达后的极短时间内忽略 Click(up)。
                        if last_click.elapsed()
                            < std::time::Duration::from_millis(120)
                        {
                            return;
                        }
                        // 挂起单击，等双击窗口期结束再决定是否打开。
                        pending_single_click = true;
                        last_click = std::time::Instant::now();
                    }
                }
                TrayEvent::DoubleClick { button, .. } => {
                    if button == tray_icon::MouseButton::Left {
                        // 取消挂起的单击，避免稍后又被当成单击打开。
                        pending_single_click = false;
                        last_click = std::time::Instant::now();
                        toggle_main_window(&open_func);
                    }
                }
                _ => {}
            }
        }

        #[cfg(windows)]
        if let Ok(data) = ipc_receiver.try_recv() {
            match data {
                Data::ControlledSessionCount(count) => {
                    _tray_icon
                        .lock()
                        .unwrap()
                        .as_mut()
                        .map(|t| t.set_tooltip(Some(tooltip(count))));
                }
                _ => {}
            }
        }

        // Windows periodic rebuild: re-apply the menu every ~300 iterations (~30 seconds)
        // This works around a Windows Explorer quirk where tray icon menu associations
        // can be lost after Explorer restarts or sleeps/resumes.
        #[cfg(windows)]
        {
            rebuild_count += 1;
            if rebuild_count >= 300 {
                rebuild_count = 0;
                if let Some(tray) = _tray_icon.lock().unwrap().as_ref() {
                    tray.set_menu(Some(Box::new(tray_menu.clone())));
                }
            }
        }
    });
}

#[cfg(windows)]
#[tokio::main(flavor = "current_thread")]
async fn start_query_session_count(sender: std::sync::mpsc::Sender<Data>) {
    let mut last_count = 0;
    loop {
        if let Ok(mut c) = crate::ipc::connect(1000, "").await {
            let mut timer = crate::luoda_interval(tokio::time::interval(Duration::from_secs(1)));
            loop {
                tokio::select! {
                    res = c.next() => {
                        match res {
                            Err(err) => {
                                log::error!("ipc connection closed: {}", err);
                                break;
                            }

                            Ok(Some(Data::ControlledSessionCount(count))) => {
                                if count != last_count {
                                    last_count = count;
                                    sender.send(Data::ControlledSessionCount(count)).ok();
                                }
                            }
                            _ => {}
                        }
                    }

                    _ = timer.tick() => {
                        c.send(&Data::ControlledSessionCount(0)).await.ok();
                    }
                }
            }
        }
        hbb_common::sleep(1.).await;
    }
}

fn load_icon_from_asset() -> Option<image::DynamicImage> {
    let Some(path) = std::env::current_exe().map_or(None, |x| x.parent().map(|x| x.to_path_buf()))
    else {
        return None;
    };
    #[cfg(target_os = "macos")]
    let path = path.join("../Frameworks/App.framework/Resources/flutter_assets/assets/icon.png");
    #[cfg(windows)]
    let path = path.join(r"data\flutter_assets\assets\icon.png");
    #[cfg(target_os = "linux")]
    let path = path.join(r"data/flutter_assets/assets/icon.png");
    if path.exists() {
        if let Ok(image) = image::open(path) {
            return Some(image);
        }
    }
    None
}
