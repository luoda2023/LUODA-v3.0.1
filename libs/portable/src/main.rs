#![windows_subsystem = "windows"]

#[cfg(windows)]
use std::os::windows::ffi::OsStrExt;
use std::{
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

use bin_reader::BinaryReader;

pub mod bin_reader;
#[cfg(windows)]
mod ui;

#[cfg(windows)]
const APP_METADATA: &[u8] = include_bytes!("../app_metadata.toml");
#[cfg(not(windows))]
const APP_METADATA: &[u8] = &[];
const APP_METADATA_CONFIG: &str = "meta.toml";
const META_LINE_PREFIX_TIMESTAMP: &str = "timestamp = ";
const APP_PREFIX: &str = "LUODA";
const APPNAME_RUNTIME_ENV_KEY: &str = "LUODA_APPNAME";
#[cfg(windows)]
const SET_FOREGROUND_WINDOW_ENV_KEY: &str = "SET_FOREGROUND_WINDOW";

fn is_timestamp_matches(dir: &Path, ts: &mut u64) -> bool {
    let Ok(app_metadata) = std::str::from_utf8(APP_METADATA) else {
        return true;
    };
    for line in app_metadata.lines() {
        if line.starts_with(META_LINE_PREFIX_TIMESTAMP) {
            if let Ok(stored_ts) = line.replace(META_LINE_PREFIX_TIMESTAMP, "").parse::<u64>() {
                *ts = stored_ts;
                break;
            }
        }
    }
    if *ts == 0 {
        return true;
    }

    if let Ok(content) = std::fs::read_to_string(dir.join(APP_METADATA_CONFIG)) {
        for line in content.lines() {
            if line.starts_with(META_LINE_PREFIX_TIMESTAMP) {
                if let Ok(stored_ts) = line.replace(META_LINE_PREFIX_TIMESTAMP, "").parse::<u64>() {
                    return *ts == stored_ts;
                }
            }
        }
    }
    false
}

fn write_meta(dir: &Path, ts: u64) {
    let meta_file = dir.join(APP_METADATA_CONFIG);
    if ts != 0 {
        let content = format!("{}{}", META_LINE_PREFIX_TIMESTAMP, ts);
        // Ignore is ok here
        let _ = std::fs::write(meta_file, content);
    }
}

fn setup(
    reader: BinaryReader,
    dir: Option<PathBuf>,
    clear: bool,
    _args: &Vec<String>,
    _ui: &mut bool,
) -> Option<PathBuf> {
    let dir = if let Some(dir) = dir {
        dir
    } else {
        // home dir
        if let Some(dir) = dirs::data_local_dir() {
            dir.join(APP_PREFIX)
        } else {
            eprintln!("not found data local dir");
            return None;
        }
    };

    #[cfg(windows)]
    if _args.is_empty() {
        *_ui = true;
        ui::setup();
    }
    if let Err(err) = std::fs::create_dir_all(&dir) {
        eprintln!("failed to create runtime directory: {err}");
        return None;
    }
    #[cfg(windows)]
    let total_bytes = reader
        .files
        .iter()
        .map(|file| file.raw.len())
        .sum::<usize>();
    #[cfg(windows)]
    let mut completed_bytes = 0usize;
    for file in reader.files.iter() {
        file.write_to_file(&dir);
        #[cfg(windows)]
        {
            completed_bytes = completed_bytes.saturating_add(file.raw.len());
            ui::set_progress(completed_bytes, total_bytes);
        }
    }
    Some(dir.join(&reader.exe))
}

fn use_null_stdio() -> bool {
    false
}

#[cfg(windows)]
fn is_windows_7() -> bool {
    use windows::Wdk::System::SystemServices::RtlGetVersion;
    use windows::Win32::System::SystemInformation::OSVERSIONINFOW;

    unsafe {
        let mut version_info = OSVERSIONINFOW::default();
        version_info.dwOSVersionInfoSize = std::mem::size_of::<OSVERSIONINFOW>() as u32;

        if RtlGetVersion(&mut version_info).is_ok() {
            // Windows 7 is version 6.1
            println!(
                "Windows version: {}.{}",
                version_info.dwMajorVersion, version_info.dwMinorVersion
            );
            return version_info.dwMajorVersion == 6 && version_info.dwMinorVersion == 1;
        }
    }
    false
}

fn execute(path: PathBuf, args: Vec<String>, _ui: bool) {
    println!("executing {}", path.display());
    // setup env
    let exe = std::env::current_exe().unwrap_or_default();
    let exe_name = exe.file_name().unwrap_or_default();
    // run executable
    let mut cmd = Command::new(path);
    cmd.args(args);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        // DETACHED_PROCESS | CREATE_NO_WINDOW = no console window at all
        cmd.creation_flags(
            winapi::um::winbase::DETACHED_PROCESS | winapi::um::winbase::CREATE_NO_WINDOW,
        );
        cmd.stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        if _ui {
            cmd.env(SET_FOREGROUND_WINDOW_ENV_KEY, "1");
        }
    }

    cmd.env(APPNAME_RUNTIME_ENV_KEY, exe_name);
    let child = match cmd.spawn() {
        Ok(child) => child,
        Err(e) => {
            let msg = format!("Failed to start LUODA:\n\n{}", e);
            #[cfg(windows)]
            {
                use std::os::windows::ffi::OsStrExt;
                let wide: Vec<u16> = std::ffi::OsStr::new(&msg)
                    .encode_wide()
                    .chain(std::iter::once(0))
                    .collect();
                unsafe {
                    winapi::um::winuser::MessageBoxW(
                        std::ptr::null_mut(),
                        wide.as_ptr(),
                        std::ptr::null(),
                        0x00000010,
                    );
                }
            }
            #[cfg(not(windows))]
            eprintln!("{}", msg);
            return;
        }
    };
    let pid = child.id();
    std::mem::forget(child);

    #[cfg(windows)]
    if _ui {
        unsafe {
            winapi::um::winuser::AllowSetForegroundWindow(pid as u32);
        }
    }
}

fn main() {
    // Set a panic hook to show a message box on panic instead of silently exiting
    #[cfg(windows)]
    std::panic::set_hook(Box::new(|info| {
        #[cfg(windows)]
        {
            use std::os::windows::ffi::OsStrExt;
            let msg = format!("LUODA encountered an error:\n\n{}", info);
            let wide: Vec<u16> = std::ffi::OsStr::new(&msg)
                .encode_wide()
                .chain(std::iter::once(0))
                .collect();
            unsafe {
                winapi::um::winuser::MessageBoxW(
                    std::ptr::null_mut(),
                    wide.as_ptr(),
                    std::ptr::null(),
                    0x00000010,
                );
            }
        }
        #[cfg(not(windows))]
        eprintln!("LUODA encountered an error:\n\n{}", info);
    }));

    let mut args = Vec::new();
    let mut arg_exe = Default::default();
    let mut i = 0;
    for arg in std::env::args() {
        if i == 0 {
            arg_exe = arg.clone();
        } else {
            args.push(arg);
        }
        i += 1;
    }
    let click_setup = args.is_empty() && arg_exe.to_lowercase().ends_with("install.exe");
    #[cfg(windows)]
    let quick_support = args.is_empty() && win::is_quick_support_exe(&arg_exe);
    #[cfg(not(windows))]
    let quick_support = false;

    let mut ui = false;
    let reader = BinaryReader::default();
    #[cfg(windows)]
    if win::activate_existing_instance() {
        if !args.is_empty() {
            if let Some(dir) = dirs::data_local_dir() {
                execute(dir.join(APP_PREFIX).join(&reader.exe), args, false);
            }
        }
        return;
    }
    if let Some(exe) = setup(
        reader,
        None,
        click_setup || args.contains(&"--silent-install".to_owned()),
        &args,
        &mut ui,
    ) {
        if click_setup {
            args = vec!["--install".to_owned()];
        } else if quick_support {
            args = vec!["--quick_support".to_owned()];
        }
        execute(exe, args, ui);
    }
}

#[cfg(windows)]
mod win {
    use std::{
        fs,
        os::windows::{ffi::OsStrExt, process::CommandExt},
        path::Path,
        process::Command,
    };
    use winapi::{
        shared::minwindef::FALSE,
        um::{
            handleapi::CloseHandle,
            processthreadsapi::OpenProcess,
            winbase::QueryFullProcessImageNameW,
            winnt::PROCESS_QUERY_LIMITED_INFORMATION,
            winuser::{
                FindWindowExW, FindWindowW, GetWindowTextW, GetWindowThreadProcessId,
                IsHungAppWindow, MessageBoxW, SetForegroundWindow, ShowWindow, MB_ICONWARNING,
                MB_OK, SW_RESTORE,
            },
        },
    };

    // Used for privacy mode(magnifier impl).
    pub const RUNTIME_BROKER_EXE: &'static str = "C:\\Windows\\System32\\RuntimeBroker.exe";
    pub const WIN_TOPMOST_INJECTED_PROCESS_EXE: &'static str = "RuntimeBroker_LUODA.exe";

    fn wide(value: &str) -> Vec<u16> {
        std::ffi::OsStr::new(value)
            .encode_wide()
            .chain(std::iter::once(0))
            .collect()
    }

    fn belongs_to_ldesk(window: winapi::shared::windef::HWND) -> bool {
        let mut process_id = 0;
        unsafe { GetWindowThreadProcessId(window, &mut process_id) };
        if process_id == 0 {
            return false;
        }
        let process = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id) };
        if process.is_null() {
            return false;
        }
        let mut path = vec![0_u16; 32768];
        let mut length = path.len() as u32;
        let ok = unsafe { QueryFullProcessImageNameW(process, 0, path.as_mut_ptr(), &mut length) }
            != FALSE;
        unsafe { CloseHandle(process) };
        if !ok {
            return false;
        }
        String::from_utf16_lossy(&path[..length as usize])
            .to_ascii_lowercase()
            .ends_with("\\luoda.exe")
    }

    fn has_ldesk_title(window: winapi::shared::windef::HWND) -> bool {
        let mut title = [0u16; 256];
        let length = unsafe { GetWindowTextW(window, title.as_mut_ptr(), title.len() as i32) };
        if length <= 0 {
            return false;
        }
        is_ldesk_title(&String::from_utf16_lossy(&title[..length as usize]))
    }

    fn is_ldesk_title(title: &str) -> bool {
        title.to_ascii_lowercase().starts_with("ldesk")
    }

    fn find_existing_window() -> winapi::shared::windef::HWND {
        let class_name = wide("FLUTTER_RUNNER_WIN32_WINDOW");
        let window_name = wide("LDesk");
        let named = unsafe { FindWindowW(class_name.as_ptr(), window_name.as_ptr()) };
        if !named.is_null() && belongs_to_ldesk(named) {
            return named;
        }
        let mut current = std::ptr::null_mut();
        loop {
            current = unsafe {
                FindWindowExW(
                    std::ptr::null_mut(),
                    current,
                    class_name.as_ptr(),
                    std::ptr::null(),
                )
            };
            if current.is_null() || (belongs_to_ldesk(current) && has_ldesk_title(current)) {
                return current;
            }
        }
    }

    pub(super) fn activate_existing_instance() -> bool {
        let window = find_existing_window();
        if window.is_null() {
            return false;
        }
        if unsafe { IsHungAppWindow(window) } != FALSE {
            let message = wide(
                "LDesk 已在运行但暂时没有响应。请稍候再试；启动器不会覆盖正在使用的程序文件。",
            );
            let title = wide("LDesk");
            unsafe {
                MessageBoxW(
                    std::ptr::null_mut(),
                    message.as_ptr(),
                    title.as_ptr(),
                    MB_OK | MB_ICONWARNING,
                );
            }
            return true;
        }
        unsafe {
            ShowWindow(window, SW_RESTORE);
            SetForegroundWindow(window);
        }
        true
    }

    pub(super) fn copy_runtime_broker(dir: &Path) {
        let src = RUNTIME_BROKER_EXE;
        let tgt = WIN_TOPMOST_INJECTED_PROCESS_EXE;
        let target_file = dir.join(tgt);
        if target_file.exists() {
            if let (Ok(src_file), Ok(tgt_file)) = (fs::read(src), fs::read(&target_file)) {
                let src_md5 = format!("{:x}", md5::compute(&src_file));
                let tgt_md5 = format!("{:x}", md5::compute(&tgt_file));
                if src_md5 == tgt_md5 {
                    return;
                }
            }
        }
        let _allow_err = Command::new("taskkill")
            .args(&["/F", "/IM", "RuntimeBroker_LUODA.exe"])
            .creation_flags(winapi::um::winbase::CREATE_NO_WINDOW)
            .output();
        let _allow_err = std::fs::copy(src, &format!("{}\\{}", dir.to_string_lossy(), tgt));
    }

    /// Check if the executable is a Quick Support version.
    /// Note: This function must be kept in sync with `src/core_main.rs`.
    #[inline]
    pub(super) fn is_quick_support_exe(exe: &str) -> bool {
        let exe = exe.to_lowercase();
        exe.contains("-qs-") || exe.contains("-qs.exe") || exe.contains("_qs.exe")
    }

    #[cfg(test)]
    mod tests {
        use super::is_ldesk_title;

        #[test]
        fn legacy_luoda_windows_are_not_reused() {
            assert!(is_ldesk_title("LDesk"));
            assert!(is_ldesk_title("LDesk - Connection Manager"));
            assert!(!is_ldesk_title("LUODA"));
            assert!(!is_ldesk_title(""));
        }
    }
}
