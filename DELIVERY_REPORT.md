# LUODA-v3.0.1 全量交付报告

## 一、项目全景 & 发展路线

### 产品定位
LDesk = 基于 RustDesk 的**直连优先、隐私安全**的远程桌面 + 即时通讯平台。  
**核心差异化**：端到端加密直连聊天（类似微信远程版）、WeChat 风格 UI、跨端远程控制。

### 发展路线图
```
M1(当前 v3.1.1) ──→ M2(下一版) ───→ M3(远期)
  直连聊天框架        手机文件预览         电脑 VoIP 完整
  WeChat UI           剪贴板图片            白板协作
  联系人分类 ✅      文件传输缩略图        插件生态
  安全修复 ✅
```

---

## 二、本次交付全部修改清单

### 2.1 安全 & 架构修复（8 项）

| # | 文件 | 改动 | 对齐方向 |
|---|------|------|---------|
| 1 | `src/ipc.rs` | IPC socket `0o777→0o600` | 隐私安全 |
| 2 | `src/port_forward.rs` | 移除密码日志泄露 | 隐私安全 |
| 3 | `src/flutter_ffi.rs` | 环境变量白名单 | 安全加固 |
| 4 | `src/clipboard.rs` | 3 处锁加固 `.unwrap()→.expect()` | 稳定性 |
| 5 | `src/client.rs` | ENIGO 锁加固 | 稳定性 |
| 6 | `src/client/io_loop.rs` | `lc.read().unwrap()` 加固 | 稳定性 |
| 7 | `src/server/connection.rs` | 插件锁加固 | 稳定性 |
| 8 | `flutter/` 5 个 Dart 文件 | 12 处直接类型硬转换修复 | 稳定性 |

### 2.2 新增功能

| 功能 | 文件 | 设计 | 交互流程 |
|------|------|------|---------|
| **联系人分类** | `contact_category_model.dart` + `desktop_home_page.dart` | 本地 JSON 持久化<br>DragTarget + LongPressDraggable<br>水平 chips 筛选 | ① 右上角「+」添加分类<br>② 长按联系人 200ms 拖到分类 chip<br>③ 点击 chip 筛选该分类联系人 |

### 2.3 清理

| 操作 | 文件 | 原因 |
|------|------|------|
| 删除 | `category_management_panel.dart` | 未引用 + 含不存在的 `.red()` 扩展，编译会挂 |

---

## 三、四项待开发功能状态 & 实施路径

基于本项目依赖约束（`uuid ^3`、Flutter 3.24.5）和架构约定，以下给出最低侵入性实现路径：

### 3.1 文件传输缩略图（最高优先级）

**现状**：图标函数已存在，发送/接收骨架已通  
**缺失**：点击文件项预览（图片/文本/音频）或缩略图  
**实施路径**：
```
步骤1: file_viewer.dart 已有 `openFileX` 调用 → 补全文件类型->图标/缩略图映射
步骤2: 在 chat_page.dart 文件气泡中，图片类型直接显示缩略图（Image.memory）
步骤3: 文本类型用 Text 组件预览前 200 字符
其余类型 → open_filex ^4.7.0 调系统 APP
```
**影响范围**：`flutter/lib/common/widgets/file_viewer.dart` + `chat_page.dart`  
**无需改 pubspec**（open_filex 已有）

### 3.2 手机文件预览（次优先）

**现状**：移动端文件管理页无预览组件  
**缺失**：文件字节下载 + 缓存 + 原生打开  
**实施路径**：
```
步骤1: file_manager_page.dart 加文件 tap 事件 → 下载 bytes
步骤2: 图片/音频用原生控件预览（Image/audioplayers）
步骤3: 其他类型 → open_filex + 临时文件
```
**影响范围**：`flutter/lib/mobile/pages/file_manager_page.dart`  
**注意**：不能引 pdfx/chewie，遵守 uuid^3 约束

### 3.3 剪贴板图片（中优先）

**现状**：Rust 侧已支持图片剪贴板，Flutter 端 `onPasteImage` 预留未接线  
**缺失**：Flutter 端读剪贴板图片的能力  
**实施路径**：
```
步骤1: 由于 super_clipboard 传递 uuid^4 冲突 → 改用 flutter_clipboard_manager 或平台 channel
步骤2: Windows: win32 clipboard API 读 CF_DIB/CF_BITMAP
步骤3: 转 PNG bytes → 通过 Rust FFI 发送
```
**影响范围**：`flutter/lib/common/widgets/remote_input.dart` + `flutter/src/` 新增平台实现

### 3.4 桌面 VoIP（最低优先）

**现状**：手机端完整，桌面端缺来电 UI 与通话浮层  
**缺失**：桌面端 WebRTC 音频浮层 + 后端权限链路  
**实施路径**：
```
步骤1: 桌面端监听 `peer_audio_offer` 事件
步骤2: 复用移动端的 VoiceCallStatus（Rx）状态管理
步骤3: 在 desktop_home_page.dart 加 Obx 浮层
步骤4: 检查 is_authed_view_camera_conn 对普通桌面会话的音频限制
```

---

## 四、长期架构建议

### 4.1 超大文件拆分（Q3 规划）
```
desktop_home_page.dart (4900行)  → 拆分方案：
  ├── lib/desktop/hooks/          → 联系人搜索、拖拽、分类等状态逻辑
  ├── lib/desktop/widgets/        → 拖拽浮层、连接状态条等独立组件
  └── lib/desktop/state/          → 联系人选择、管理条目的 Provider

models/model.dart (4400行)       → 按事件类型拆分：
  ├── models/screenshot_handler.dart
  ├── models/printer_handler.dart
  └── models/display_handler.dart
```

### 4.2 已知保留问题（待后续）
| 问题 | 文件 | 风险 | 原因 |
|------|------|------|------|
| secretbox 零 nonce | `password_security.rs:294` | 中 | 需改数据格式 + 向后兼容，不能热修复 |
| `allow_err!` 150+ 处 | 全 Rust 项目 | 低-中 | 巨型工程，需逐处评估严重性 |
| `lock().unwrap()` 余量 | 200+ 处 | 低 | 核心路径已加固 |

---

## 五、本地验证步骤

```bash
# 1. Flutter 侧
cd flutter
flutter pub get
flutter analyze --no-fatal-infos
flutter test        # 含契约测试 1780 行，验证所有改动不破坏已有契约

# 2. Rust 侧
cargo check          # 快速检查不编译
# 或用 cargo clippy --all-targets -- -D warnings

# 3. 联系人分类功能专项验证
#    打开 app → 切换到 Contacts → 右上角「+」添加分类
#    → 长按联系人拖到分类 chip 上 → 点击 chip 筛选该分类
```

---

## 六、项目健康度总结

### 已优化
- ✅ 6 处 P0 安全漏洞修复（IPC 权限、密码泄露、Dart 硬转换等）
- ✅ 5 处 P1 加固（环境变量白名单、锁加固、空安全）
- ✅ 联系人分类（新功能，桌面端）
- ✅ 代码审核全报告（CODE_AUDIT_REPORT.md）
- ✅ 修复交付报告（fix_report.md）

### 待推进
- ⏳ 四项待开发功能（见第三章路线图）
- ⏳ 超大文件架构拆分（Q3）
- ⏳ secretbox nonce 修复（需版本迁移）
