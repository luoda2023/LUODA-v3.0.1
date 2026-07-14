#[cfg(windows)]
fn build_windows() {
    // Link libsodium for Windows
    if let Ok(sodium_lib_dir) = std::env::var("SODIUM_LIB_DIR") {
        println!("cargo:rustc-link-search=native={}", sodium_lib_dir);
    }
    // MSVC: vcpkg installs sodium.lib => link "sodium"
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

    // Embed Windows PE resource (FileVersion / ProductVersion / icon / manifest)
    // from [package.metadata.winres] in Cargo.toml. The version fields are
    // populated automatically from the package `version` (3.0.1) via
    // CARGO_PKG_VERSION; values in [package.metadata.winres] take precedence.
    // Failure is non-fatal: some toolchains may lack rc.exe/windres, in which
    // case we emit a cargo warning and continue producing the binary.
    let res = winres::WindowsResource::new();
    if let Err(e) = res.compile() {
        println!("cargo:warning=winres compile failed: {e}");
    }
    println!("cargo:rerun-if-changed=Cargo.toml");
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
    #[cfg(target_os = "windows")]
    build_windows();
    #[cfg(target_os = "macos")]
    build_mac();
}
