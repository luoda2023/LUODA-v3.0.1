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

## [09-04 05:0x] 新APK(v3.1.24含Rust音频直推补丁)实测记录
### 关键背景修正
- ⚠️ jniLibs/libluoda.so 之前是 9/2 旧核心! 音频直推补丁(Rust connection.rs 3:38改)根本没进 APK.
- 5:07 已重新构建含补丁 APK(arm64+x86_64), 两端 5:08 安装成功. Rust 核心现已最新.
### 真机相机权限
- OPPO PFUM10 上 CAMERA 曾 granted=false + USER_FIXED(用户曾拒"不再询问") → 手机被查看摄像头必然失败.
- 已通过 设置→权限管理→摄像头→"使用时允许" 手动授予 granted=true. USER_FIXED 清除.
- ⚠️ 授权中心 6/6 项不含相机. Video call 依赖系统 CAMERA 权限, 若用户曾拒绝需手动到系统设置开启.
### 实测结果(新核心)
1. 远程协助 P2P: 真机→模拟器(ID 31 205916) 成功! 模拟器被控端显示 7/7授权+断开连接, 会话建立. (方向A通)
2. 模拟器→真机(ID 31 979354): 卡"正在连接..." 不通. 模拟器172.16.1.17(emulator NAT) 与真机192.168.31.70 不同网段, ping不通 → 走 relay/打洞路径有障碍.
3. 断开连接: 模拟器被控端点"断开连接"后无确认弹窗, UI 残留被控态; 实际 TCP 已断. (UI状态残留bug)
### 待测
- 聊天窗口内 远程协助/语音/视频 各入口
- 语音电话/视频电话 双端
- 会议/会议纪要/文件传输

## [09-04 12:5x] 语音/视频通话链路深度排查（手机↔手机不通 + 杂音 + 页面卡死）
### 复现环境
- OPPO PFUM10 真机(192.168.31.70) + emulator-5556(模拟器, NAT 172.16.1.17, 设备 ID 31839036)。两端均为 v3.1.24。
- 真机曾作为被控端授权 MediaProjection 录屏 + AudioRecordHandle 采集系统音频(playback capture)。
### 已确认现象
1. 模拟器↔真机已有 P2P 聊天会话(P2P直连 192.168.31.70:27369 加密TCP, 保活聊天)，但聊天窗点"语音通话"不直接复用该会话发语音，而是 `_startRemoteFromChat()` 用设备 ID 拨号 → rendezvous/打洞(跨网段 NAT)失败 → 永远卡"正在连接..."。
2. 模拟器进入被控端授权面板(协助tab)：屏幕录制开、音频录制开 → 一旦有会话(远程协助/来电) 主控可听到被控端系统采集的音频。
3. RemotePage/ViewCameraPage：WillPopScope 返回键只 clientClose(断连) 不 pop，会话黑屏/断连后页面无法退出 → 只能杀进程。
4. 语音来电未接受时，若被控端已开投屏+音频录制，主叫端可能先听到被控端系统声音(来电铃声等) → "没确认就有声音/杂音"。
5. 语音"呼叫中"(waitingForResponse) 若对端不应答，无超时自动放弃，持续占屏。
### 代码事实
- Dart: `_startVoiceCallFromChat`(home_page.dart 1152): 仅 connType==defaultConn/viewCamera 才 sessionRequestVoiceCall；chat 会话(connType==chat)会走 _startRemoteFromChat 重新拨号(可能失败)。
- Rust connection.rs 799-807: view_camera 连接授权+audio_enabled 且 voice_calling==false 时条件 `voice_calling||!audio_enabled()` = false||false = false → 不订阅(正确)；但普通 remote 连接(788-790 else)无条件 subscribe(audio_enabled) → 远程协助期间传系统音频是设计行为。
- audio_service Android 循环: 无条件 get_audio_raw→Opus→广播; 播放采集(AudioRecordHandle.startAudioRecorder) 与 语音采集共用 AUDIO_RAW 缓冲。
- flutter_ffi sessionRequestVoiceCall→ui_session_interface request_voice_call→Data::NewVoiceCall→io_loop 发 VoiceCallRequest(is_connect=true)+on_voice_call_waiting。
- server connection.rs 4015: 收到 VoiceCallRequest is_connect → send_to_cm(VoiceCallIncoming)；accept → handle_voice_call(accepted) 开麦。

## [09-04 15:3x] 手机↔手机 语音/视频电话真机复现（v3.1.24 现存问题清单）
### 复现现象（真机 OPPO PFUM10 + 模拟器 emulator-5556）
1. 真机在与模拟器的点聊聊天窗内点顶部"语音通话"(864,184)：日志显示
   [VoiceCallFromChat] enter peer=31205916 → [RemoteFromChat] dial by pure ID
   → [FFI_START] connType 仍旧是 chat → "Exit session event loop"。
   结果：UI 卡在"正在连接..."弹窗(RemotePage 黑屏加载层)，**按返回键无法退出**（WillPopScope return false），只能 force-stop。
2. 根因：移动端是单 FFI/单 sessionId 架构。点聊聊天保活会话(connType=chat,
   pi.isSet=true)占用全局 gFFI；从聊天窗发起语音走 _startRemoteFromChat()→connect()
   用同一 sessionId 再 start(defaultConn)，session_add 检测到同 id 不同 conn_type
   → 旧会话被 try_send_close_event 关闭("Exit session event loop")，新拨号没有真正
   建立（旧会话释放与新会话获取之间无协调），于是永远"正在连接"。
3. 杂音："没确认接收就有声音" 因为在 view_camera/defaultConn 会话授权后
   connection.rs 788-807 会对 audio_enabled 且 voice_calling==false 的普通 remote
   连接无条件 subscribe 系统音频；来电尚未 accept 时主叫已能听到被叫端系统声。
### 修复方向
- 移动端从点聊发起语音/视频前，必须先 await gFFI.close() 关闭纯聊天保活会话，
  再以 defaultConn/viewCamera 拨号；拨号成功进入 RemotePage/ViewCameraPage 后
  自动 request_voice_call（一次到位，不需要用户再点一次语音按钮）。
- RemotePage/ViewCameraPage 返回键：会话未断先 clientClose；会话已断(closed)或
  用户确认后真正 Navigator pop；监听 UI "close" 事件自动退出黑屏层。
- waitingForResponse 加超时(45s)自动挂断复位 UI。
- Rust:VoiceCallRequest is_connect 到达且未 accept 前，暂时关闭该 conn 的 audio
  订阅；accept 后 handle_voice_call 再按 voice_calling 订阅，避免来电响铃被当系统
  音频推给主叫。

## [09-04 17:2x] 语音/视频电话不应依赖远程协助（录屏）服务 — 架构诊断
### 用户核心诉求（多次强调）
- 语音电话、视频电话、视频会议是独立通话功能，**不该反开远程协助（录屏）功能**。
- 连接方式不变：P2P 直连优先、少占中继。某一方承担组织会议角色即可。
### 根因（代码实证）
1. Dart home_page._startVoiceCallFromChat/_startVideoCallFromChat（1154/1191 行）：
   - isActiveRemote 仅认 defaultConn/viewCamera；**connType==chat 的点聊保活连接被排除**。
   - 无活动远程会话时走 _dialCallSession() 关闭聊天会话 → 以 defaultConn/viewCamera **重拨一条“远程控制/摄像头”新连接**。
   - 被叫端因此必须以“可被远程控制”(录屏协助服务在线)状态接收 → 语音电话被错误绑定到远程协助。
2. Rust 侧能力其实已具备：
   - client/io_loop.rs 1010: Data::NewVoiceCall 直接 peer.send(new_voice_call_request(true))（无 chat 类型限制）。
   - client/io_loop.rs 2219: 收到 VoiceCallRequest is_connect 目前 TODO 忽略（主叫视角）。
   - client/io_loop.rs 2142/2149: voice_call_active 时把对端 AudioFrame 推 Dart（on_voice_call_audio_frame）。
   - server/connection.rs 4015: 收到 VoiceCallRequest is_connect → send_to_cm(VoiceCallIncoming)（被叫 host 视角，无 chat 限制）。
   - 移动端音频：Dart VoiceCallAudio 采集麦克风/opus 编码 → sessionSendVoiceCallAudio；播放走 onVoiceCallAudioFrame→feedIncomingOpus。不依赖录屏授权。
### 结论
语音/视频通话**不需要**录屏协助服务，只需一条已建立的 P2P 连接(含点聊 chat 连接)。
修复方向：点聊聊天页发起语音/视频时，若已有同一对端 chat P2P 连接(pi.isSet && !closed && connType==chat)，
直接复用该连接 sessionRequestVoiceCall，不再重拨 defaultConn/viewCamera；并补齐聊天页内通话 UI(等待/计时/挂断)。
### 测试环境事实
- OPPO PFUM10(7358bbbb, Android12) 息屏策略极强：screen_off_timeout 约8-10s、svc power stayon 不生效、WRITE_SETTINGS 被拒。
- 需高频 KEYCODE_WAKEUP(仅唤醒不滑动) 保持亮屏；滑动唤醒会误触“接受”按钮。
- 模拟器 emulator-5556 与 OPPO 跨网段(172.16.1.x vs 192.168.31.x)，点聊聊天 P2P 可通(192.168.31.70:27369)，说明 P2P 复用可行。
- 桌面端 Ld9BoxHeadless(PID 25304) 残留连接 OPPO:27369，测试前需确认不干扰。
- 来电弹窗“接受”按钮真实像素 ≈ (851,1490)；45s 等待超时会自动挂断，须在超时内点接受。

## [09-04 21:5x] 来电UI修复关键进展(v3.1.25) — 全局handler + 顶层来电层
### 已确认根因(代码实证+双端真机)
1. voice-call 事件(update_voice_call_state/on_voice_call_*)此前只经 _eventCallback 可达，
   而 _eventCallback 仅 serverModel.startService() 设置 -> 手机停主页/聊天窗时来电事件被静默丢弃。
   - 修复: main.dart _registerEventHandler 移动端分支注册 6 个全局 handler
     (update_voice_call_state/on_voice_call_waiting/started/closed/incoming/voice_call_audio_frame)。
2. 来电UI层(_MobileIncomingCallLayer)原挂在 HomePage Stack，但聊天窗 ChatPage 经
   Navigator.push 全屏路由盖住 HomePage -> 在聊天窗时来电 UI 不可见。
   - 修复: 公开化为 MobileIncomingCallLayer 并挂到 GetMaterialApp builder(Android) 顶层 Stack,
     覆盖所有路由; HomePage 内嵌实例已移除。
3. server_model.updateVoiceCallState Android 分支的 showVoiceCallDialog(dialogManager) 与来电层
   双 UI 冲突 -> Android 分支改为只走状态机(来电层负责 Accept/Reject)。
### 实测(v3.1.25 arm64/x86_64 双APK 21:41)
- 模拟器(31205916)在主页收到 OPPO(31979354)语音来电: 来电卡正常弹出(收到语音通话/OPPO-PFUM10/拒绝/接受)。
- Rust 日志确认被叫端 voice_call_incoming -> update_voice_call_state -> call_main_service_set_by_name fail(正常空跑)。
- 反向 OPPO 被叫(在聊天窗内) 来电 Rust 日志正常(VC-DBG id=281 peer=31205916) 但 UI 无弹卡
  = HomePage层被ChatPage路由遮挡的复现证据 -> 顶层来电层修复后需重测。
### 遗留待验证
- OPPO logcat 无 flutter debugPrint(进程20945) - ColorOS 节流或 release 树摇, 需用 Rust log:: 侧确认。
- push_event 已加 log::debug [PUSHDBG](Android logcat 可见), 重编后确认 OPPO stream 是否注册。
- accept 后未进 VoiceCallPage/通话未连通: 待顶层层修复后完整重测 语音 accept->connected->音频。

## [09-05 06:0x] 语音通话主叫卡Calling + 复用已死点聊连接 修复（APK v3.1.24 ece955f）
### 代码修复
1. voice_call_page.dart 全量重写：Obx(依赖构建偶发不重建) -> 显式 voiceCallStatus.listen 订阅 + setState 驱动；
   加每秒 Timer 兜底同步 + PopScope(canPop:false, onPopInvoked -> hangUp) + popUntil 兜底退出（页面可能压在多层路由上）。
   实测日志: initState waitingForResponse -> status -> connected (订阅触发刷新) -> 计时；hang up -> notStarted -> 自动退出。
2. home_page.dart _ensureChatAndDialVoice 重写：拨语音前若走 chat P2P 复用路径一律 force:true 强制重拨(打破半开死连)；
   固定900ms等待 -> 4s轮询就绪(200ms间隔)；超时才回退 _dialCallSession。
### 实测(方向A 模拟器主叫 -> OPPO被叫, 两机同APK)
- OPPO 在聊天窗被叫收到来电层(拒绝/接受)正常。
- OPPO accept -> 模拟器主叫 [VoiceCallPage] status->connected（修复前卡 Calling 不再复现）。
- 双向音频: OPPO 被叫 cmSendVoiceCallAudio called conn=425 上行；模拟器主叫 recv audio frame len=125~130 status=connected 下行。
- OPPO 通话页计时正常；模拟器主叫计时正常(截图确认 Voice call - 00:xx)。
- 模拟器主叫点挂断 -> [hang up] -> 两端均自动回主页(来电层/通话页清理干净)。
### 遗留
- 方向B(OPPO主叫->模拟器被叫) 受 OPPO ColorOS 熄屏策略限制(需组合键 MENU+APP_SWITCH+HOME+WAKEUP 偶发点亮) 未能完整跑通；
  历史 bugs 记录该方向打洞不稳(真机NAT方向)。
- OPPO 屏幕点亮依赖真实物理操作, adb 无法稳定保持。
## [09-05 06:2x] 模拟器端会议/远程协助功能验证(新APK ece955f)
- Meeting tab: Start meeting 创建成功(TestMeeting0905, 主持人31046892) -> 自动出现在点聊列表(Group chat) -> 群聊页工具栏 Enter to Watch/Add member/Voice call/More 齐全。
- 会议页: Start presentation 成功(出现 End presentation) -> 演示/观看入口正常。
- Assist tab: Start service -> MediaProjection 授权(系统 START NOW) -> 远程协助服务在线(控制面板 Copy/Disconnect 出现)。
- 单实例无法测"他端加入观看/远程协助连入"，需第二设备(OPPO)。

## [09-05 07:3x] 语音通话双端验证(v3.1.25 ece955f+屏常亮) - 方向A/B均通
### 代码变更(ece955f 之后的 v3.1.25)
1. MainActivity.kt: 新增 mChannel 方法 keep_screen_on/keep_screen_off = FLAG_KEEP_SCREEN_ON + PowerManager WakeLock(SCREEN_BRIGHT_WAKE_LOCK|ACQUIRE_CAUSES_WAKEUP|ON_AFTER_RELEASE, tag voicecall, 10min上限) 双保险。
2. chat_model.dart: 新增 _setVoiceCallScreenOn(bool), 在 onVoiceCallWaiting/Started(通话中)、onVoiceCallIncoming(来电)、onVoiceCallClosed(结束释放) 处调用。目的: OPPO/ColorOS/华为强省电ROM通话/来电不熄屏。
### 实测(模拟器31046892 <-> OPPO 31979354, 同APK v3.1.25)
- 会话重建: 模拟器重装APK后 current ID 不变(UI My QR 显示 31 046892, info1-id 839168671 是内部临时id非点聊id)。OPPO 端 Add friend(31046892) 成功 -> 模拟器陌生人组出现 OPPO-PFUM10。
- 方向A(模拟器主叫->OPPO被叫): OPPO 来电层(拒绝/接受)正常; accept -> 模拟器 status connected; 双向音频 OPPO cmSendVoiceCallAudio conn=630 上行, 模拟器 recv audio 128-129 下行; 计时正常; 挂断后两端自动回主页。
- 方向B(OPPO主叫->模拟器被叫): OPPO 聊天窗语音 -> 短暂"正在连接..." -> 模拟器来电层弹出 -> accept -> 模拟器 setVoiceCallConnId=743 + status connected + recv OPPO 上行(128-129); OPPO sessionSendVoiceCallAudio 上行。模拟器被叫 startCapture begin 但无 pcm chunk(=无头模拟器虚拟mic无数据, 环境限制非代码bug; 被叫cmSend路径在方向A的OPPO被叫已验证)。
- WakeLock: OPPO 发起语音时 logcat 确认 OplusAONSmartDim: onWakeLockAcquireLocked flags=0x3000000a tag=voicecall 获取成功。
### 遗留
- OPPO ColorOS 即使在通话中(前台Activity+FLAG+WakeLock) 长时静置仍可能息屏(AON智能调光), 需前台服务/通知或用户允许后台才可靠; 建议后续加"通话中保持屏幕"设置并引导用户允许自启动。
- 方向B模拟器被叫上行受模拟器无头mic限制无法实测(同代码路径方向A已验证)。
