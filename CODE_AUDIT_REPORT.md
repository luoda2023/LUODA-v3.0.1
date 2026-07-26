# LUODA-v3.0.1 代码审核总报告

**审核日期**：2026-07-25
**审核范围**：`src/` (155 Rust 文件) + `flutter/lib/` (156 Dart 文件)
**审核方法**：静态代码分析 + 模式扫描（TODO/FIXME、`unwrap()`、`allow_err!`、`lock().unwrap()`、硬编码密钥、0o777、as cast）
**注意**：本沙箱无 flutter/rustc 工具链，无法执行 `cargo clippy` / `flutter analyze`，以下结论基于静态源码分析

---

## 一、发现汇总

| 严重度 | 安全漏洞 | Panic/unwrap | 并发/死锁 | 错误处理 | 架构/可维护性 |
|--------|---------|--------------|----------|---------|------------|
| 🔴 严重 (P0) | 6 | 10+ | — | — | — |
| 🟠 高危 (P1) | 8+ | 50+ | 200+ | 150+ | 4 |
| 🟡 中危 (P2) | 15 | — | — | — | — |
| 🟢 低危 (P3) | — | — | — | — | 5 |

---

## 二、🔴 P0 — 严重问题（必须立即修复）

### 2.1 2FA 加密密钥硬编码为 `"00"`（`src/auth_2fa.rs`）
- L55 / L66 / L124：`encrypt_vec_or_original(..., "00", 1024)` / `decrypt_vec_or_original(..., "00")`
- 2FA TOTP secret 和 Telegram bot token 使用固定密钥 `"00"` 加密
- **影响**：攻击者只需知道此代码，即可解密所有用户的 2FA secret
- **修复**：改用平台密钥派生（Windows DPAPI / macOS Keychain / Linux libsecret）

### 2.2 secretbox 使用零 nonce `[0;32]`（`libs/hbb_common/src/`）
- secretbox 加密使用固定零 nonce，**完全破坏加密安全性**
- 同一密钥+同一 nonce 会生成相同密文，且可被攻击者恢复明文
- **修复**：每次加密使用 `gen_array!([u8; 32])` 生成随机 nonce

### 2.3 IPC socket 文件权限 0o777（`src/ipc.rs`）
- L446 / L1073：`std::fs::set_permissions(&path, 0o0777)`
- IPC socket 文件 world-writable，任何本地用户可向 IPC 通道注入任意消息
- **影响**：本地提权 / IPC 劫持
- **修复**：改为 `0o600` 或 `0o660`，限制为本用户访问

### 2.4 端口转发密码明文打印日志（`src/port_forward.rs`）
- L33：`println!("{:?}", args)` — 明文打印包含密码的命令参数
- L23-24：密码通过 `cmdkey /pass:{}` 明文拼接，可见于进程列表
- **影响**：密码泄露到日志和进程快照
- **修复**：移除 println；改用 cmdkey 的交互方式或临时文件

### 2.5 更新机制无签名/哈希验证（`src/updater.rs`）
- 更新包下载后未进行签名验证或哈希校验
- **影响**：供应链攻击 — 恶意更新包可被植入
- **修复**：下载后验证 RSA/Ed25519 签名 + SHA256 哈希

### 2.6 Dart 硬转换运行时崩溃（`flutter/lib/`）
- `desktop_setting_page.dart:94-104`：`jsonDecode(...) as bool`，若原生返回字符串则崩溃
- `desktop_home_page.dart:214`：`as RenderBox` 硬转换，嵌套 Navigator 场景下可能不匹配
- `http_service.dart:94`：`parsedJson['headers']` 无 null 检查
- **修复**：改用 safe cast 或类型判断

---

## 三、🟠 P1 — 高危问题

### 3.1 `lock().unwrap()` 全项目泛滥（200+ 处）
关键路径：
- `client.rs`：`ENIGO.lock().unwrap()`（L472）、`udp.lock().unwrap()`（L776/L799）
- `server/connection.rs`：`PLUGIN_BLOCK_INPUT_TXS.lock().unwrap()`（L179）
- `clipboard.rs`：`ARBOARD_MTX.lock().unwrap()`（L334/L380/L419）
- `io_loop.rs`：`connection_round_state.lock().unwrap()`（L181）
- `rendezvous_mediator.rs`：`mtx.lock().unwrap()`（L903/L909）

**问题**：`Mutex::lock()` 在 panic 时返回 `PoisonError`，`unwrap()` 后级联崩溃整个进程
**修复**：关键路径改用 `.lock().expect("context")`，非关键路径用 `.lock().ok()` + 降级逻辑

### 3.2 `allow_err!` 滥用静默吞异常（150+ 处）
关键位置：
- `client.rs`：`allow_err!(s.connect(...).await)`（L857/L866）— 关键连接失败无重试
- `client.rs`：`allow_err!` 包裹 `peer.send()`（L3528/L3996/L4061）— 控制消息发送失败无感知
- `client/io_loop.rs`：20+ 处 `peer.send()` 全部 `allow_err!`
- `common.rs`：`allow_err!(do_check_software_update())`（L949）— 更新检查线程 panic 无监控
- `rendezvous_mediator.rs`：打洞/中继/内网发现全部 `allow_err!`
- `flutter_ffi.rs`：插件 API 调用全部 `allow_err!`

**影响**：安全事件无审计日志，连接失败用户无感知，调试困难
**修复**：关键操作替换为带日志的错误传播

### 3.3 FFI 任意环境变量暴露（`src/flutter_ffi.rs`）
- L1323：`SyncReturn(std::env::var(key).unwrap_or_default())`
- `key` 未做白名单限制，Flutter UI 可读取任意环境变量（API token、SSH key 等）
**修复**：添加环境变量白名单（仅允许 `RUST_*` / `RUSTDESK_*` 前缀）

### 3.4 Telegram bot token 明文拼接 URL（`src/auth_2fa.rs`）
- L159：`format!("https://api.telegram.org/bot{}/sendMessage", bot.token_str)`
- Token 以明文直接拼入 URL，在日志/内存/网络抓包中完整暴露
**修复**：使用 Authorization header 或至少脱敏日志输出

### 3.5 Dart `unawaited()` 缺少 `.catchError`（10+ 处）
- `main.dart` 启动逻辑、`direct_chat.dart` 同步、`chat_page.dart` IconButton async 回调
- 静默吞异常，崩溃无日志
**修复**：添加 `.catchError` 或改为 `await`

### 3.6 Dart 非空断言崩溃（`models/model.dart`）
- L564 / L636：`parent.target!.dialogManager` — parent 为 null 时直接崩溃
**修复**：改用可选链 `parent.target?.dialogManager` + 空值处理

### 3.7 Dart `int.parse()` 无保护（`models/model.dart`）
- L905 / L1494 等多处：`evt['display']` 为 null 时直接抛 TypeError
**修复**：添加 null 检查和默认值

### 3.8 Dart `jsonDecode` 外层无 try-catch（`connection_page.dart`）
- L220：`jsonDecode(await bind.mainGetConnectStatus()) as Map` — 解析失败直接崩溃
**修复**：包裹 try-catch

### 3.9 Dart `http_service.dart` 敏感数据泄露
- L101：将原始 response 体放入异常消息，可能泄露敏感数据
**修复**：异常消息中脱敏 response body

### 3.10 Dart 内存泄漏风险（Listener 未 dispose）
- 多个 widget 中 `NotificationListener` / `StreamSubscription` 未在 `dispose()` 中取消
**修复**：在 `State.dispose()` 中显式取消订阅

---

## 四、🟡 P2 — 中危问题

### 4.1 TLS 实现存在不安全降级选项（`libs/hbb_common/src/tls.rs`）
**修复**：移除不安全的降级路径，强制 TLS 1.2+

### 4.2 git 依赖未锁定提交（`Cargo.toml`）
**修复**：锁定所有 git 依赖到具体 commit hash

### 4.3 Dart 重复代码模式
- 文件类型 icon/color：两个几乎相同的 switch 枚举（`chat_page.dart`），应合并为配置表
- 时间格式化 `'HH:mm'` 模式在 5+ 处重复，应提取 `formatTime()` 工具函数

### 4.4 Dart 超大文件（架构风险）
| 文件 | 行数 | 建议 |
|------|------|------|
| `desktop_home_page.dart` | 4,895 | 拆分路由/状态/组件 |
| `common.dart` | 4,679 | 拆分 FFI/工具/协议 |
| `models/model.dart` | 4,419 | 按职责拆分为多个 model |
| `desktop_setting_page.dart` | 4,046 | 按设置类别拆分 |

### 4.5 Dart 上帝组件（`desktop_home_page.dart`）
- 单一 State 包含 50+ 方法和 40+ 成员变量
- 违反单一职责原则，难以测试和维护
**修复**：拆分为 Provider / 自定义 Hook

### 4.6 Dart `FfiModel` 职责过多（`models/model.dart`）
- 事件分发 + msgBox + 截图 + 打印 + 键盘 + 权限，共 20+ 职责
- `startEventListener` 闭包 ~190 行 if-else 链处理 50+ 事件类型
**修复**：按领域拆分为多个子模型

### 4.7 `ClipboardSide::is_owner()` 边界漏洞（`src/clipboard.rs`）
- L518-523：`data[0] & 0b11 != 0`，当 data 为 `[0b00]` 时返回 true
**修复**：添加 data 长度边界检查

### 4.8 多处 TODO 未处理（全项目 50+ 处）
关键 TODO：
- `main.dart:284`：`// FIXME: fix display index`
- `lan.rs:166`：`// TODO: maybe we should use a better way to get ipv4 addresses`
- `gestures.dart:123`：`// FIXME: This debounce logic is not working properly`
- `clipboard.rs:423`：`// FIXME`
- `remote_input.dart:33`：`// FIXME: On Windows, AltGr will generate Alt and Control key events`

### 4.9 Dart `as Map/as List` 强制转换风险（全项目）
- `direct_chat.dart`、`direct_pairing.dart`、`desktop_home_page.dart` 等多处
- `as Map<String, dynamic>` 在无类型保证的场景下运行时可能崩溃
**修复**：改用 `Map.from()` 或类型判断

---

## 五、🟢 P3 — 低危问题（建议优化）

- Flutter SDK 版本过旧（stable-3.24.5），建议跟踪 LTS
- `sodiumoxide` crate 维护度较低，考虑替代方案
- Dart `generated_bridge.freezed.dart` 自动生成，无需手动维护
- 构建脚本缺少 `SODIUM_LIB_DIR` 验证
- Dart 字符串拼接建议使用 `StringBuffer` 替代大量 `+` 操作

---

## 六、修复优先级路线图

```
P0（本周）：
├── auth_2fa.rs: "00" → 平台密钥派生
├── ipc.rs: 0o777 → 0o600
├── port_forward.rs: 移除密码 println
├── secretbox: 零 nonce → 随机 nonce
├── updater.rs: 添加签名验证
└── Dart 硬转换 → safe cast

P1（本月）：
├── lock().unwrap() → expect / ok 降级
├── allow_err! → 带日志传播
├── flutter_ffi.rs: 环境变量白名单
├── auth_2fa.rs: Telegram token 脱敏
└── Dart unawaited → catchError

P2（下季度）：
├── 超大文件拆分
├── 重复代码提取
├── TLS 加固
├── git 依赖锁定
└── TODO 清理

P3（持续）：
├── Flutter SDK 升级
├── sodiumoxide 替代评估
└── 字符串拼接优化
```

---

## 七、工具链建议

由于本沙箱缺少 flutter/rustc 工具链，建议在本地带完整工具的机器上运行：

```bash
# Rust 侧
cargo clippy --all-targets --all-features -- -D warnings -W clippy::all

# Flutter 侧
cd flutter && flutter analyze --no-fatal-infos
cd flutter && flutter test

# 覆盖率
cargo tarpaulin --all-targets
```

这些工具可以发现本静态分析遗漏的编译期错误和 lint 问题。
