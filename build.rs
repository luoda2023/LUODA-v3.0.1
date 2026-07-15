#[cfg(windows)]
fn build_windows() {
    // Link libsodium for Windows
    if let Ok(sodium_lib_dir) = std::env::var("SODIUM_LIB_DIR") {
        println!("cargo:rustc-link-search=native={}", sodium_lib_dir);
    }
    // MSVC: vcpkg installs libsodium.lib (output of builds/msvc/vs2022/libsodium.vcxproj)
    // GNU/MinGW: vcpkg installs libsodium.a => link "libsodium"
    #[cfg(target_env = "msvc")]
    println!("cargo:rustc-link-lib=libsodium");
    #[cfg(not(target_env = "msvc"))]
    println!("cargo:rustc-link-lib=libsodium");

    let file = "src/platform/windows.cc";
    let file2 = "src/platform/windows_delete_test_cert.cc";
    cc::Build::new().file(file).file(file2).compile("windows");
    println!("cargo:rustc-link-lib=WtsApi32");
    println!("cargo:rerun-if-changed={}", file);
    println!("cargo:rerun-if-changed={}", file2);
}

#[cfg(target_os = "macos")]
fn build_mac() {
    let file = "src/platform/macos.mm";
    let mut b = cc::Build::new();
    if let Ok(os_version::OsVersion::MacOS(v)) = os_version::detect() {
        let v = v.version;
        if v.contains("10.14") {
            b.flag("-DNO_InputMonitoringAuthStatus=1");
        }
    }
    b.flag("-std=c++17").file(file).compile("macos");
    println!("cargo:rerun-if-changed={}", file);
}

fn main() {
    #[cfg(windows)]
    build_windows();
    #[cfg(target_os = "macos")]
    build_mac();

    // Embed res/icon.ico into the Windows executable so the OS taskbar /
    // Explorer / shell display the LUODA-branded icon for luoda.exe.
    println!("cargo:rerun-if-changed=res/icon.ico");

    #[cfg(windows)]
    {
        let mut res = winres::WindowsResource::new();
        res.set_icon("res/icon.ico");
        res.set("FileDescription", "LUODA Remote Desktop");
        res.set("ProductName", "LUODA");
        if res.compile().is_err() {
            // Toolchain may not have rc.exe in PATH; fall back silently.
        }
    }
}

