pub const VERSION: &str = "3.1.1";
#[allow(dead_code)]
pub const BUILD_DATE: &str = "2026-05-25 15:10";

/// LUODA 3.x 协议最低版本要求。任何低于此版本的客户端/服务端将被拒绝连接，
/// 实现新版与老版（1.x/2.x）的完全协议级分离。
#[allow(dead_code)]
pub const MIN_PEER_VERSION: &str = "3.0.0";

/// Version-mismatch login error message returned to peers below MIN_PEER_VERSION.
#[allow(dead_code)]
pub const LOGIN_MSG_VERSION_MISMATCH: &str =
    "Version incompatible. Please update to LUODA 3.0.0 or later.";
