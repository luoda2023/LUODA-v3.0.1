# LUODA 六项问题修复交付报告

> 生成时间：2026-07-25
> 范围：用户提出的 6 项问题（被控端弹窗 / 鼠标偏移 / 文件图片传输 / 撤回入口 / VPS直连 / 启动黑屏）
> 状态：**6 项已全部落码修复（#2 鼠标偏移已实现自动按受控端每显示器 DPI 换算，方向与 macOS 一致）；全部改动未经本机编译，待构建/真机验证**

---

## 0. 构建环境限制（务必先读）

本沙箱环境 **没有 `flutter` / `dart` SDK，也没有 `vcpkg` / `sciter`**（C++ 依赖），因此：

- **Flutter/Dart 改动（#1 弹窗的 Flutter 兜底、#3、#4、#6）无法在此编译**，需你本地 `flutter pub get && flutter analyze && flutter build`。
- **Rust 改动（#1 的 Rust 授权、#5 配置）也无法在此 `cargo build`**（缺 vcpkg 的 libvpx/libyuv/opus/aom 与 sciter）。
- 所有改动已按既有代码模式与标准 API **逐行静态复核**，但**未经编译/运行验证**。请在你本地带完整工具链的机器上构建验证。

---

## 1. 被控端"访问对方设备"弹窗 —— ✅ 已修复

**根因**：`src/server/connection.rs` 的 `handle_login_request` 中，聊天直连（`chat_only`）对**未知联系人**走 `else if self.chat_only` 分支，把 `authorized=false`，被控端据此弹出授权卡片/对话框。已知联系人虽被 `direct_chat_auto_allowed` 自动同意，但未知联系人仍弹窗。

**修复**：`connection.rs:2625` 的 `chat_only` 分支改为与已知联系人一致——先 `send_logon_response_and_keep_alive()` 真正授权，再 `try_start_cm(..., self.authorized)`。

```rust
} else if self.chat_only {
    // LUODA FIX: chat/file/voice (isChat) 直连后台自动同意，不弹窗
    if err_msg.is_empty() {
        if !self.send_logon_response_and_keep_alive().await { return false; }
        self.try_start_cm(lr.my_id, lr.my_name, self.authorized);
    } else {
        self.send_login_error(err_msg).await;
    }
    return true;
}
```

**效果**：聊天/文件/语音（isChat）连接被控端后台默认同意；仅真正远程桌面控制（非 `chat_only`）仍弹窗。
**验证**：控制端发起聊天/发文件/发语音，被控端不再弹"Request access to your device"，连接直接建立。

---

## 2. 鼠标实际位置比看到的偏高 —— ✅ 已修复（自动识别受控端每显示器 DPI）

**根因（已确定性定位）**：
- enigo 在 Windows 的 `mouse_move_to`（`libs/enigo/src/win/win_impl.rs:128`）用
  `MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK` 经 `SendInput`，
  把传入的 `evt.x/evt.y` 当作**物理虚拟桌面坐标**（归一化到 `SM_CX/VIRTUALSCREEN`）。
- 控制端发来的 `evt` 由 `_handlePointerDevicePos`（`input_model.dart:1777`）基于 `rect`（物理像素）换算，即控制端发送的是**物理像素坐标**。
- 但受控 Windows 的 `DisplayInfo.scale` 被**硬编码为 1.0**（`display_service.rs:346` 原仅有 macOS/Linux 分支），且坐标换算只在 **macOS** 的 `Retina::on_mouse_event`（`connection.rs:5711`，物理→逻辑 `/scale`）实现，Windows 完全没有对应处理。
- 当被控 Windows 显示缩放 ≠ 100%（如 125%/150%）时，enigo 在（任意 DPI 感知模式下）期望的是**逻辑坐标**，而收到的仍是物理坐标，相差 `scale` 倍，表现为"实际落点比看到的更高"。

**已修复（本轮回退已落地，不再只是诊断）**：
1. `libs/scrap/src/dxgi/mod.rs`：新增 `Display::dpi_scale()`，用 `GetDpiForMonitor(hmonitor, MDT_EFFECTIVE_DPI)` 取每显示器有效 DPI，`scale = dpi/96`。
2. `libs/scrap/src/common/dxgi.rs`：透传 `Display::scale()`（Windows 与 macOS/Linux 接口统一）。
3. `libs/scrap/Cargo.toml`：为 winapi 增加 `shellscalingapi` feature（`GetDpiForMonitor` 所需）。
4. `src/server/display_service.rs`：新增 `#[cfg(windows)] scale = d.scale();`，让 `DisplayInfo.scale` 上报真实 DPI。
5. `src/server/connection.rs`：受控端收到 `MouseEvent` 后、`input_mouse` 前，新增 `#[cfg(windows)] Self::on_mouse_event_windows()`，按坐标所在显示器查到真实 `scale`，把物理坐标除以 `scale` 转成逻辑坐标（与 macOS `Retina::on_mouse_event` 同构；多屏用坐标矩形选屏，逐屏按自身 scale 换算）。`s<=1.0` 或坐标不在任何屏内时不做改动，100% 缩放机器行为不变。

**方向正确性论证（关键，消除"盲改"风险）**：
控制端发物理像素；受控 enigo（`MOUSEEVENTF_ABSOLUTE`）在 DPI 感知或未感知进程下都接收**逻辑坐标**（Windows 会自动把逻辑换算到物理），因此"物理÷scale→逻辑"与 macOS 视网膜路径同理，**方向确定正确**，不依赖脆弱的进程 DPI 感知假设。沙箱无 Windows 真机，无法跑 `cargo build`，但已逐行静态复核。

**验证步骤**：在一台 **显示缩放 150% 的 Windows 被控机**上构建测试，点击四角/边缘。
- 光标偏移**消失** → 修复生效。
- 100% 缩放机器应无任何变化（s==1 公式恒等）。
- 若极个别环境（如 secure-desktop/portable service 子进程未 DPI 感知）仍偏，可在该子进程入口补 `SetProcessDpiAwareness(2)`，方向不变。

---

## 3. 不能发文件 / 不能粘贴图片 / 无预览 —— ✅ 已修复（内联字节方案）

**根因**：此前聊天发文件只发了元数据（fileName/size/sha/localPath），**文件实体字节未走传输子系统**，对方无实体可预览。

**修复（直连协议内联文件字节）**：
- `direct_chat.dart`：给 `DirectChatRecord` 增加瞬态字段 `inlineBytes`（base64，仅走信封、不落历史）；`DirectChatEnvelope.message()` 在 `inlineBytes` 非空时写入 `inline_bytes`；新增 `kMaxInlineChatFileBytes = 5MB` 与接收落盘辅助 `saveInlineChatFile()`（存到 `应用文档/luoda_chat_received/`）。
- `chat_model.dart`：
  - `sendFileRecord`：发送前若 `localPath` 文件存在且 ≤5MB，读字节 base64 内联进消息。
  - `receive`：收到 `inline_bytes` 且为文件消息时，落盘并写回 `localPath`，预览即可直接打开。
- 剪贴板粘贴图片（`clipboard_image_sender.dart` → `sendFileRecord`）自动复用上述链路，截图/图片可粘贴发送。
- 预览组件 `file_viewer.dart`（`resolveReceivedFilePath` 已递归搜文档目录）可直接定位落盘文件。

**效果**：图片、截图、小文件（≤5MB）通过聊天直连真实发送并可预览；接收方点击气泡即开图/播视频/看 PDF。
**限制**：>5MB 的大文件当前仍只发元数据（完整文件传输子系统对接未接，属后续工作）。5MB 上限覆盖绝大多数图片与小型文档。
**验证**：A 发图片/附件 → B 立即收到并在气泡点击预览；粘贴截图发送同理。

---

## 4. 撤回 / 自毁入口太隐蔽 —— ✅ 已修复

**修复**（`chat_page.dart`）：自己发出的、未撤回的消息，气泡右侧由原先一个极小的 `more_horiz` 改为：
- 显眼的**红色「撤回」按钮**（`undo_rounded`，一键撤回）+ 操作菜单按钮（更多/自毁/销毁）。
- 撤回为一键直达，不再需要先点开菜单。

```dart
final actionButton = canManage
    ? Row(children: <Widget>[
        IconButton( // 显眼撤回
          onPressed: () async {
            final changed = await chatModel.recallMessage(message);
            if (context.mounted && changed) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text(translate('Message recalled'))));
            }
          },
          style: IconButton.styleFrom(
            backgroundColor: dark ? const Color(0x33FF6B6B) : const Color(0x1AE5484D)),
          icon: Icon(Icons.undo_rounded, color: ...),
        ),
        IconButton(onPressed: () => _showMessageActions(context, message), ...), // 更多
      ])
    : const SizedBox(width: 30, height: 30);
```

**验证**：发出的消息右侧可见红色撤回按钮；点更多可见自毁/销毁。

---

## 5. VPS 上 ID / 直连 IP 不能访问 —— ✅ 已修复（对齐 branding 意图）

**根因**：`libs/hbb_common/src/config.rs` 的 `RENDEZVOUS_SERVERS` 是编译期默认/兜底常量，运行时若未在「网络 / ID·中继」里设置「自定义 rendezvous 服务器」，就会用它连 hbbs。此前常量指向硬编码 IP `47.114.75.115:21116`（与 VPS 域名不一致）；上一轮对齐 branding 文档时**误写成 `luoda.dicad.cn`**，而实际可用域名是 `rev.dicad.cn`（运行日志 `rev.dicad.cn:21116` 握手正常、延迟 ~200ms，`src/client.rs` 与 `connection_page.dart` 也均硬编码 `rev.dicad.cn`）。

**修复**：`config.rs` 常量改为正确的 `rev.dicad.cn`，并同步修正 `BRANDING_SUMMARY.md` / `GITEE_ACCESS_GUIDE.md` 中误写的 `luoda.dicad.cn`：

```rust
// LUODA FIX: canonical rendezvous server is `rev.dicad.cn`.
// `RS_PUB_KEY` must match the hbbs `id_ed25519.pub` on that server.
pub const RENDEZVOUS_SERVERS: &[&str] = &["rev.dicad.cn:21116"];
pub const RS_PUB_KEY: &str = "OQnLEvt6xjfPCUc1ozpTUiAxijwnn624zy0GH9IxX90=";
```

**改法（两种）**：
- A. 编译期写死（推荐，对所有用户生效）：改 `libs/hbb_common/src/config.rs` 的 `RENDEZVOUS_SERVERS` 常量 → 重新构建。
- B. 运行时覆盖（无需重编）：在 app「网络 / ID·中继」设置里填「自定义 rendezvous 服务器 = `rev.dicad.cn`」，该值写入 `rendezvous-servers` 配置并优先于常量生效。

**部署必要条件（请核对）**：
1. `rev.dicad.cn:21116` 上的 hbbs 必须**可达**，且其公钥 == `RS_PUB_KEY`；否则所有 ID/relay 握手失败。
2. 被控端所在网络需放行 TCP **21118**（直连端口，回退 21118–21128）；VPS 云安全组需入站放行 21118。
3. 注意：`DEFAULT_DIRECT_PORT(21118)` 与 `WS_RENDEZVOUS_PORT(21118)` 同值；若 hbbs 与被控端同机，需给被控端单独设 `direct-access-port`（如 21128）避免端口冲突。

**验证**：用 ID 连接、用裸 IP 直连均成功；relay 正常。

---

## 6. 程序启动黑屏一下 —— ✅ 已修复

**根因**：主窗口 `backgroundColor: Colors.transparent` 在 Windows 不被支持、退化为黑色；且 `windowManager.show()` 早于 Flutter 首帧，OS 默认黑背景先显示。

**修复**（`flutter/lib/main.dart`）：
- `getHiddenTitleBarWindowOptions`：主窗口背景改为主题画布色（深/浅随主题），仅 macOS 保留原生透明标题栏。
- `waitUntilReadyToShow` 回调：`show()` 前 `await WidgetsBinding.instance.endOfFrame`，确保首帧画完再显示。

```dart
backgroundColor: (isMacOS && isMainWindow)
    ? null
    : (isMainWindow
        ? (MyTheme.currentThemeMode() == ThemeMode.dark
            ? MyTheme.canvasDark : MyTheme.canvasLight)
        : Colors.transparent),
// ...
} else {
  await WidgetsBinding.instance.endOfFrame; // 先画后显，消除黑闪
  windowManager.show();
  windowManager.focus();
  luodaWinManager.registerActiveWindow(kWindowMainId);
}
```

**验证**：启动直接进入应用主题色界面，无黑色闪烁。

---

## 7. 本地构建与验证清单

```bash
# Flutter 侧
cd flutter && flutter pub get && flutter analyze
flutter build windows   # 桌面
flutter build apk       # 安卓

# Rust 侧（需 vcpkg + sciter 环境）
cargo build --release
```

逐项验收：
- [ ] #1 被控端聊天/文件/语音连接不再弹"访问设备"窗，远程桌面仍弹
- [ ] #3 图片/截图/小文件可发送并预览（≤5MB）
- [ ] #4 自己消息右侧有显眼撤回按钮
- [ ] #5 用 ID 与裸 IP 均能连接你的 VPS
- [ ] #6 启动无黑屏
- [ ] #2 在 150% DPI 的 Windows 被控机上回归验证鼠标偏移（修复已落码，方向已论证正确，按第 2 节验证步骤确认）

## 8. 待办 / 风险
- **#2 已落码（自动按受控端 DPI 换算）**，仍建议在 150% DPI 真机回归一次鼠标偏移确认（方向已论证正确，见第 2 节）。
- #3 大文件（>5MB）传输子系统对接未做，如需支持大文件请另立项。
- 所有改动未经本机编译（工具链缺失），请按第 7 节本地构建。
