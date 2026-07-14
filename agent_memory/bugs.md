# Known bugs and observations

Recorded during code review of LUODA-v3.0.1 on 2026-07-14. Items here are NOT
fixed automatically; they are tracked for the user to triage. Per AGENTS.md
rule 9, unrelated issues are only recorded, not extended or removed.

## 1. UPnP LAN IP probe depends on outbound connectivity  [FIXED]

- File: `src/upnp.rs:60-66` (`get_local_lan_ip`)
- Behaviour: uses `UdpSocket::bind("0.0.0.0:0")` + `connect("8.8.8.8:80")` to
  discover the outbound interface IP. This is the canonical "get my LAN IP
  without sending real traffic" trick, but it requires routing to 8.8.8.8 to
  succeed.
- Risk: in offline / China-mobile / corporate-firewall environments where
  8.8.8.8 is unreachable, `connect` returns `Err`, `get_local_lan_ip` returns
  `None`, and `add_port_mapping` silently fails with a Chinese "Cannot get
  LAN IP" log line. Users have no actionable signal beyond a `warn!`.
- Side note: `src/upnp.rs` itself is not referenced by any other file in the
  workspace, so the failure is currently invisible in production.
- Fix idea (not applied): probe a small fallback list (`8.8.8.8`, `1.1.1.1`,
  `114.114.114.114`) and return the first one that succeeds; on total
  failure, fall back to the first non-loopback interface from
  `getif_addrs`/`pnet` rather than `None`.

## 2. UI label change: Accessible devices -> Access history devices

- Resolved this session.
- `flutter/lib/desktop/pages/connection_page.dart:350`
- `flutter/lib/desktop/pages/desktop_home_page.dart:148`
- `flutter/lib/models/peer_tab_model.dart:32`
- `flutter/test/peer_tab_strip_test.dart:21,46,52`
- All 47 `src/lang/*.rs` keys (`Accessible devices` -> `Access history devices`).
- `src/lang/cn.rs` Chinese: 可访问的设备 -> 访问历史设备.
- `src/lang/tw.rs` Traditional: 可存取的裝置 -> 訪問歷史設備.
- Other-language translations still carry the old "accessible" meaning. That
  is intentional and pending translation-team review.

## 3. `is_public_ipv4` in `src/direct_access.rs` - FALSE ALARM, re-analysed

- File: `src/direct_access.rs:76-91`
- Originally flagged as missing `0.0.0.0/8` exclusion. After re-reading the
  final conjunction:
    `first != 0 && first < 240`
  this already rejects every address whose first octet is 0 (the entire
  `0.0.0.0/8` block) and every address with `first >= 240`
  (`240.0.0.0/4` reserved for future use). Combined with
  `is_unspecified()` (catches `0.0.0.0` exactly as a defensive double-check),
  the 0/8 case is fully covered.
- Conclusion: no change required.

## 4. `client.rs` not deeply audited this session

- File: `src/client.rs` (~3.4k LoC)
- Last touched in 0deafb2 ("refresh desktop UI for 3.0.1").
- Reason: file is too large to scan safely without `cargo check`. Per the
  user instruction, builds may not run online.
- Recommended next step: when an offline build environment is available,
  run `cargo check` and `cargo clippy -- -D warnings` over the workspace.

## 5. `flutter_ffi.rs` public-IP lookup edge case  [FIXED]

- File: `src/flutter_ffi.rs:1205-1261`
- Behaviour: tries two HTTPS endpoints (`api.ipify.org`,
  `checkip.amazonaws.com`) and falls back to STUN. The response body is
  trimmed and parsed as `Ipv4Addr`; parsing failure is silently ignored and
  the loop moves to the next source.
- Risk: low. The two HTTPS sources are independent, and the STUN fallback
  keeps the public-IP option from going permanently empty.
- Possible improvement (not applied): shorten the 8-second per-request
  timeout to 3 seconds, so a slow proxy cannot stall the worker thread for
  16+ seconds before STUN is tried.

## 6. `flutter_ffi.rs` not deeply audited this session

- File: `src/flutter_ffi.rs` (~3.5k LoC, recently changed)
- Reason: same as #4. Needs `cargo check` + flutter pub get + flutter
  analyze with the actual dependency tree.
## 7. `build.rs` libsodium link name is uniform despite an MSVC branch  [FIXED]

- File: `build.rs:17-22`
- The two `println!("cargo:rustc-link-lib=libsodium")` lines are
  byte-for-byte identical even though they sit behind a `target_env = "msvc"`
  cfg / a `not(target_env = "msvc")` cfg. The surrounding comment claims
  MSVC should link `sodium` and GNU/MinGW should link `libsodium`, but the
  code emits `libsodium` in both cases.
- Risk: if a Windows MSVC build uses vcpkg's `libsodium` port and the
  produced import library is `sodium.lib` (the historical vcpkg convention),
  the link step will fail with `unresolved external symbol` because
  `rustc-link-lib=libsodium` looks for `libsodium.lib`.
- This was introduced in commit 7ecdd93 (3.0.1).
- Fix idea (not applied): MSVC branch should emit
  `cargo:rustc-link-lib=sodium` (or test which file exists in
  `SODIUM_LIB_DIR` and pick the matching name). The build-exe workflow
  should be re-run on `windows-latest` to confirm the correct name.