#![cfg_attr(
 all(not(debug_assertions), target_os = "windows"),
 windows_subsystem = "windows"
)]

#[cfg(target_os = "macos")]
use hbb_common::{config, log};
#[cfg(target_os = "macos")]
use luoda::*;

#[cfg(not(target_os = "macos"))]
fn main() {}

#[cfg(target_os = "macos")]
fn main() {
    crate::common::load_custom_client();
    hbb_common::init_log(false, "service");

    // Set preset permanent password for macOS service
    if !config::Config::has_permanent_password() {
        log::info!("service: presetting permanent password {}", config::DEFAULT_PERMANENT_PASSWORD);
        config::Config::set_permanent_password(config::DEFAULT_PERMANENT_PASSWORD);
    }

    // Set platform-specific default security options for macOS service
    {
        use hbb_common::config::keys;
        if config::Config::get_option(keys::OPTION_ACCESS_MODE).is_empty() {
            log::info!("service: setting default access-mode=full");
            config::Config::set_option(keys::OPTION_ACCESS_MODE.to_string(), "full".to_string());
        }
        if config::Config::get_option(keys::OPTION_APPROVE_MODE).is_empty() {
            log::info!("service: setting default approve-mode=click");
            config::Config::set_option(
                keys::OPTION_APPROVE_MODE.to_string(),
                "click".to_string(),
            );
        }
        if config::Config::get_option(keys::OPTION_ENABLE_KEYBOARD).is_empty() {
            log::info!("service: setting default enable-keyboard=Y");
            config::Config::set_option(keys::OPTION_ENABLE_KEYBOARD.to_string(), "Y".to_string());
        }
        if config::Config::get_option(keys::OPTION_DIRECT_SERVER).is_empty() {
            log::info!("service: setting default direct-server=Y");
            config::Config::set_option(keys::OPTION_DIRECT_SERVER.to_string(), "Y".to_string());
        }
    }

    crate::start_os_service();
}
