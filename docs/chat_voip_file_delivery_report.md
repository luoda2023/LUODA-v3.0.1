# LUODA 四项聊天/文件/语音功能 — 实现交付报告

> 实现者：高级开发工程师（全栈）。状态：源码级实现完成；沙箱无 Flutter/Dart/Rust 工具链，**未做编译验证**，需用户在本地 `flutter pub get` + 构建后实测。

## 一、四项功能实现概况

### 1. 聊天文件传输 UI（不同文件图标）
- 文件气泡改为可点击（`InkWell`），点击打开预览。
- 图片类文件显示缩略图（`Image.file`），其余文件显示按扩展名着色的类型图标（复用既有 `fileTypeIcon` / `fileTypeColor`）。
- 发送文件时把本地路径带进聊天记录，预览即可直接读本地文件。

### 2. 手机端 / 桌面文件预览组件（新增）
- 新文件 `flutter/lib/common/widgets/file_viewer.dart`，全屏路由 `showFileViewer(...)`。
- 按扩展名分流预览：
  - 图片：`Image.file`（可缩放）
  - 视频：`video_player` + `chewie`
  - PDF：`pdfx`
  - 音频：`audioplayers`（复用现有依赖，`setSource(DeviceFileSource)`）
  - 文本：可滚动只读
  - 其他：`open_filex` 调起系统应用打开
- 接收方无 `localPath` 时，按「文件名 + 大小」在下载/文档/相册等目录做最佳匹配；找不到则提示通过文件传输接收。

### 3. 图片/截图剪贴板粘贴发送（新增）
- 新文件 `flutter/lib/common/clipboard_image_sender.dart`。
- 用 `super_clipboard` 跨平台读取剪贴板 PNG → 写入临时文件 → `sendFileRecord(localPath)` 作为图片消息发出。
- 桌面 / 移动 `ChatPage` 已接入 `onPasteImage`（桌面原本就预留了按钮，现在接通）。

### 4. 电脑端 VoIP 语音通话（Rust 后端）
- 放宽 `src/server/connection.rs` 中 `handle_voice_call` / `close_voice_call` 的 `is_authed_view_camera_conn()` 限制：去掉仅 ViewCamera 会话才订阅麦克风的 `if` 包裹，改为按 `accepted && audio_enabled()` 订阅，打通普通桌面远控会话的双向音频。
- 前端来电/通话 UI 此前已存在（桌面主机侧 `server_page.dart`、工具栏 `remote_toolbar.dart`），本次补齐后端音频路由即可生效。

## 二、改动文件清单

| 文件 | 改动 |
| --- | --- |
| `flutter/lib/common/direct_chat.dart` | `DirectChatRecord` 增加 `localPath` 字段（含构造/copyWith/toJson/fromJson/createOutgoing） |
| `flutter/lib/models/chat_model.dart` | `sendFileRecord` 透传 `localPath`；`_toChatMessage` 写入 `ldesk_local_path` |
| `flutter/lib/common/widgets/file_viewer.dart` | **新增** 跨平台文件预览组件 |
| `flutter/lib/common/clipboard_image_sender.dart` | **新增** 剪贴板图片读取 + 发送 |
| `flutter/lib/common/widgets/chat_page.dart` | 文件气泡可点击 + 图片缩略图；导入 `dart:io` 与 `file_viewer` |
| `flutter/lib/desktop/pages/desktop_home_page.dart` | 发送处传 `localPath`；`ChatPage` 接 `onPasteImage`；导入 helper |
| `flutter/lib/mobile/pages/home_page.dart` | 发送处传 `localPath`；`ChatPage` 接 `onPasteImage`；导入 helper |
| `flutter/pubspec.yaml` | 新增 `video_player`/`chewie`/`pdfx`/`open_filex`/`super_clipboard` |
| `src/server/connection.rs` | 放宽语音通话音频订阅限制（VoIP） |

## 三、设计决策
- **不改 protobuf**：预览取数走 `localPath`（发出方可靠）+ 接收端下载目录最佳匹配。未强行挂钩「文件传输完成事件 → 聊天记录」，避免文件名重复导致的错误匹配与隐私风险。
- **跨平台安全**：剪贴板图片选用 `super_clipboard`（全平台支持），避免桌面专用插件拖垮移动端构建。
- **音频播放兼容**：`audioplayers 6.x` 已无 `setSourceDeviceFile`，统一改为 `setSource(DeviceFileSource(path))`。

## 四、新增依赖（pubspec.yaml）
```
video_player: ^2.8.1
chewie: ^1.8.1
pdfx: ^2.3.0
open_filex: ^5.5.0
super_clipboard: ^0.8.18
```
> 若 `flutter pub get` 报 SDK/版本冲突，按需下调版本号即可（例如 `pdfx` 对 Flutter 版本较敏感）。

## 五、需用户在本地验证（沙箱无法 build）
1. `flutter pub get`（处理可能的版本冲突）。
2. `flutter analyze` 查静态错误。
3. 各端 `flutter build`（Android 需 NDK；`super_clipboard` 仅在**写入**剪贴板时需要 AndroidManifest 的 `DataProvider`，本次仅读取，一般无需）。
4. **VoIP 实测**：桌面被控端收到来电 → 接听 → 双方均有声音。
5. **文件预览**：发出图片/PDF/视频/音频，在手机与桌面点击气泡可预览。
6. **剪贴板图片**：桌面复制截图后点「发送图片」按钮或粘贴，对端收到图片消息。

## 六、风险与未覆盖点
- 接收方文件内容预览依赖「文件已通过文件传输收到且文件名/大小可匹配」；若对端尚未接收或文件名重复，会回退为「提示通过文件传输接收」，不会误开错误文件。
- Rust 改动仅放开音频订阅限制，未触碰信令；若控制端（发起方）对普通桌面会话有额外拦截，需另行排查。
- 本机无 Flutter/Dart/Rust 工具链，所有改动按既有代码模式与标准 API 编写，但**未经编译/运行验证**。

---

## 七、直连聊天保活 + 空闲自动重连（本次新增）

### 问题背景
- 用户反馈：给对方发消息时经常「发送不出去」；希望连续发消息时保持持续在线、对方即时收到；长时间不发才断开，断开后按固定间隔自动重连以接收消息。

### 根因
- 发送出口 `_sendWire`（`chat_model.dart`）在会话未存活（`ffi==null/closed`、控制端 `pi` 未连、或找不到已授权聊天客户端）时返回 false，消息滞留 pending。
- 移动端复用全局 `gFFI`，发送前不确保 isChat 连接在线；桌面端重连受 `direct-chat-always-on` 等开关门控，且仅在「有待发消息」时建连，不为「接收」主动重连。

### 确认参数
- 保活窗口（空闲超时）：**10 分钟** → `ChatModel.kChatKeepAlive`
- 断开后重连频率：**10 秒** → `ChatModel.kChatReconnectInterval`
- 生效范围：**所有聊过天的会话**（按 `DirectChatRepository.conversationIds()`）

### 关键改动
1. **`chat_model.dart`**
   - 新增 `_lastChatActivity`（每个会话最后收发时间）、常量 `kChatKeepAlive`/`kChatReconnectInterval`、辅助 `isChatActive(peerId)` / `lastActiveChatPeerId` / `_touchChatActivity`。
   - 新增 `ensureChatConnection` 回调：发送失败且无连接时，由页面层建立会话，连上后 `onDirectSessionReady` 自动重发 pending + `syncRequest` 拉漏发。
   - 在 `receive`（收）、`onDirectSessionReady`（连上）、`_transmitRecord`（发成功）、`_sendMessage`/`sendFileRecord`/`sendVoiceClip`（发意图）处刷新活动时间。
2. **桌面 `desktop_home_page.dart`**
   - `_refreshDirectSessions` 改为调用 `_maintainChatKeepAlive()`（取代仅待发的 `_maintainPendingChatSessions`）。
   - 逻辑：活动窗口内保持连接在线；空闲超时后每 10s 重连一次拉取消息（短保活 4s 再断）；正在查看的会话不主动断开；受「常驻在线」开关管控的可信联系人仍由 `_maintainTrustedChatSessions` 全权保活（新增 `_isTrustedAlwaysOn` 避免与空闲逻辑相互拉扯）。
   - `initState` 注入 `ensureChatConnection`；`dispose` 取消空闲关闭定时器。
3. **移动 `connection_page.dart`**
   - `initState` 注入 `ensureChatConnection = _startDirectChat`，并启动 10s 周期性 `_maintainChatKeepAlive`（对最近活跃会话保持/恢复 isChat 连接；正在远程控制 `ConnType.defaultConn` 时不抢占全局 gFFI）；`dispose` 清理。

### 已知限制
- 移动端为单 `gFFI`，空闲时**不主动断开**（保持最近会话连接以确保能接收），仅桌面多会话实现「空闲断开 + 周期重连」。
- 仍依赖既有 `onDirectSessionReady` 的 pending 重发 + `syncRequest` 拉取机制，未改协议。

### 本地验证建议
- 桌面：连续发消息对方即时收到；停发 >10min 后连接断开，但仍每 ~10s 自动重连拉取新消息。
- 移动：进入会话即可发消息；后台/空闲时仍能周期性收到对方消息。
- 同前：需 `flutter pub get` / `flutter analyze` / 各端 build 验证（沙箱无工具链）。
