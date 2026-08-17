# Known unrelated issues

- The Git object database was missing tree `0e16cff9798c389bbd1b50e80b5d8ec7aaf56afa`; a non-destructive refetch restored normal status/rebase operations. Automatic GC still reports an older missing object `2e63764fa783053603a5065689acc1561d4aff93` from unrelated history.
- Full `flutter analyze` includes existing errors under `flutter/dynamic_layouts/example/test/` because the example package imports cannot be resolved. Files changed for the chat, remote session, Android build, and icon fixes have no analyzer errors.
- The optional Rust `cli` feature is stale: `src/cli.rs` still implements the old `Interface` method set and does not compile against the current client trait. This does not affect the Flutter desktop/mobile builds or runtime connection paths.
- Full Windows `cargo test --features flutter` has three unrelated machine/session failures: `custom_server::test::test_filename_license_string` depends on a machine-specific key, while `platform::tests::test_cursor_data` and `platform::tests::test_get_cursor_pos` cannot read the cursor in the non-interactive Codex desktop session. Relevant connection, viewer, chat, and file-transfer tests pass when run directly.
- Targeted cross-page `flutter analyze` still reports 46 pre-existing warnings/info items in `chat_page.dart`, `desktop_home_page.dart`, and `mobile/remote_page.dart` (unused/dead code, redundant null checks, string interpolation style, and deprecated APIs). The Bluetooth, contacts, connection-details, and remote-service files changed in the 2026-08-11 UI pass each analyze cleanly.

- `flutter/test/interaction_stability_contract_test.dart` ??failed direct chat sessions stay offline and keep messages queued?????? `chat_model.dart::_sendWire` ???????????? `!ffi.ffiModel.pi.isSet.isTrue` ?????????? `ffi==null||closed` + `isDirectChatPermissionDenied(lastError)` + ???????? CM client??????????????? ID ??/??????????????????????????

## 2026-08-08 fixed: direct chat rejected over rendezvous/relay path
- Root cause: client secure_connection (relay/hole-punch path) did not attach signed identity (signed_id + identity_public_key), so host create_tcp_connection left authenticated_peer_id unset -> direct_chat_identity_matches false -> permission denied even with everyone-mode. Direct-TCP path already carried identity (hence the open-details-dialog workaround).
- Fix: attach identity in src/client.rs secure_connection; normalized ID compare in src/server/direct_chat_policy.rs + src/server/connection.rs; desktop UI no longer prefers showing rejected when an inbound session exists (desktop_home_page.dart _directDeliveryStatus).
- Built: Releases\LDesk-windows-x64-fix-20260808-1108.zip (full bundle, luoda.dll + LDesk.exe rebuilt 2026-08-08 11:04/11:07). cargo test --lib direct_chat_policy: 12 passed.
- Remaining edge: pinned key direct-chat-peer-keys-v1 mismatch still rejects even in everyone-mode; clear that option on the host if a device reinstalled/regenerated keys.

## 2026-08-08 fixed (afternoon session)
- rendezvous_mediator.rs restored to intended state (elapsed_safe + should_use_tcp_rendezvous + tests + removed UDP-disable on Win Server). cargo check --features flutter OK; direct_chat_policy 12 passed; new should_use_tcp_rendezvous test passed.
- Remote toolbar: added "切换桌面" (Switch Desktop) viewport-cycle button immediately to the right of the 显示/Display menu, shown only when the remote has >1 display (remote_toolbar.dart _QuickDisplaySwitchButton + cn/en translations).
- Headless VPS / MSTSC disconnect: replaced one-shot headless virtual-display plug with a 15s runtime watchdog in src/server.rs; when all displays vanish (RDP session closed), the watchdog re-plugs the usbmmidd virtual display so remote control keeps working. Requires the usbmmidd driver (installed by --install-idd / installer; shipped under usbmmidd_v2 in the bundle).
- Android: arm64-v8a built with cargo-ndk (flutter,use_dasp,mediacodec) + APK rebuilt. armeabi-v7a blocked: vcpkg never built libvpx/aom/opus for arm-neon-android (only arm64/x64 exist); building armv7 needs a long vcpkg install first.
- Deliverables: Releases\LDesk-windows-x64-fix-20260808-1217.zip (luoda.dll 12:14 + LDesk.exe 12:17), Releases\LDesk-3.1.1-arm64-v8a-20260808.apk (libluoda.so 12:19).

## 2026-08-08 fixed (final delivery)
- Switch Desktop button now ALWAYS visible in the remote toolbar, immediately right of the Display menu (previously hidden unless remote reported >1 display). Disabled when remote has only one display; enabled when 2+ displays are detected. Patched flutter/lib/desktop/widgets/remote_toolbar.dart; flutter analyze: no errors; remote_window_chrome_contract_test.dart 7/7 passed.
- Windows rebuild (Flutter only, Rust luoda.dll reused from 12:14): Releases\LDesk-windows-x64-fix-20260808-1251.zip (LDesk.exe + data/app.so 12:50).
- Android: armeabi-v7a completed via vcpkg arm-neon-android triplet + cargo-ndk; Releases\LDesk-3.1.1-universal-arm64-armv7-20260808.apk (112MB, both ABIs verified).

## 2026-08-09 04:10 ?????????
- ????????: ?? 334273 -> A 423156, fix_005/006/007 + platform_test_0405 ?? delivered, src_platform=mobile ??.
- DirectChatRecord ?? srcPlatform ??(wire 'src_platform'), ??????? mobile/desktop; ???????+?????????????????(?????).
- ???????: ??????(#F7F7F7), ???????????(client.isChat && !disconnected).
- ??: cn.rs/en.rs "LUODA Remote Assistance"->"?? DotChat", "About LUODA"->"????/About DotChat".
- ????????: status_num ?? get_online_state()(rendezvous ??), B/C ??"?????"= ???????(?? 08-08 ????/??????). ?? 0405 ????? 20000-40000 + ???????.
- VPS ??: ?? setup-headless-vps.bat(usbmmidd_v2 ????? + AutoAdminLogon + ??? + ??????). ?? MSTSC ????????????.
- ??: ???"???PC/????"??; ????????; ?????UI????(?????).
