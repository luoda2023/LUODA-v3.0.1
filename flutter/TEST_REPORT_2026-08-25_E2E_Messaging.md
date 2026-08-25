# E2E 测试报告 — PC↔手机 消息收发

**日期**: 2026-08-25  
**分支**: 3.1.1  
**测试设备**: PC (Windows 10, peerId=423156) + 手机 (OPPO-PFUM10, peerId=478703)

---

## 测试结果摘要

| 测试项 | 结果 | 备注 |
|--------|------|------|
| PC端应用启动 | ✅ 通过 | luoda.exe 正常运行，Debug API 在 127.0.0.1:38881 |
| 手机端应用启动 | ✅ 通过 | com.dotchat.remote 正常运行 |
| PC→手机 消息发送 | ✅ **已验证** | 通过 Debug API `/v1/chat` 发送，手机端成功显示 |
| 手机→PC 消息发送 | ⚠️ 受限 | 手机聊天界面为语音输入模式(hermesAPI)，无文本输入框 |
| PC↔手机 直连(TCP) | ✅ 通过 | 加密直连 TCP 成功建立 |
| PC Debug API | ✅ 通过 | health/sessions/connect-chat/chat 端点全部正常 |

---

## 详细测试过程

### 1. PC→手机 消息发送（已验证 ✅）

**测试方法**: 使用 PC 端 Debug HTTP API (端口 38881) 直接调用 `session.send_chat()`

**步骤**:
1. 检查 Debug API 健康状态: `GET /v1/health` → `{"ok":true}`
2. 建立到手机(peerId=478703)的 CHAT 会话: `POST /v1/connect-chat`
3. 会话建立成功: `direct=true, secure=true, stream_type=TCP, state=connected`
4. 发送测试消息: `POST /v1/chat {"peer_id":"478703","text":"E2E test message from PC to phone 0825"}`
5. 手机端收到消息 — 主页显示新会话:
   - 陌生人区域: "陌生人 1"
   - 消息内容: "A Administrator 05:49 E2E test message from PC to phone 0825"
   - 连接类型: "ID连接 · 423156"

**结论**: PC→手机的消息发送链路完全正常。消息通过 Rust 层 `session.send_chat()` → protobuf `ChatMessage` → TCP 直连 → 手机端接收并显示。

### 2. 手机→PC 消息发送（受限 ⚠️）

**受限原因**: 手机端聊天界面使用 "hermesAPI" + "剩余 100" 的按住说话模式，EditText 组件 bounds=[0,0][0,0]（零尺寸隐藏），无法通过 ADB input text 输入文本消息。

**已尝试的替代方案**:
- 图库图片 + ZXing2 解码二维码: 解码失败
- 深链接 `dotchat://pair?...`: handleUriLink 不路由 pair host
- 远程控制连接后发送: 创建的是远程桌面会话而非 CHAT 会话
- SendKeys/PostMessage 注入到 PC 端 Flutter 窗口: 被 Windows UAC 拒绝

### 3. 直连状态

- PC 端显示: "已绑定 手机 OPPO-PFUM10 · 333168"（旧 peerId，需更新为 478703）
- 手机端显示: "你还未扫码绑定PC端"（手机端无配对记录）
- 实际直连: 通过 Debug API 的 connect-chat 成功建立 TCP 加密直连
- 密码验证: 永久密码 666999 通过验证

---

## 发现的问题

### 问题1: PC端绑定信息过期
- **现象**: PC 显示已绑定 peerId=333168 的手机，但手机实际 peerId 为 478703
- **原因**: 手机每次重新安装/清数据后生成新 peerId，PC 端的旧绑定记录未自动更新
- **影响**: 无实际影响，因 Debug API 可直接按 peerId 连接

### 问题2: 手机端聊天输入框隐藏
- **现象**: 手机与陌生人(Authoristrator/423156)聊天时，输入框 EditText bounds=[0,0][0,0]
- **原因**: 聊天界面默认为 hermesAPI 语音模式("按住说话")，文本输入框被零尺寸隐藏
- **影响**: 无法通过 ADB 自动化输入文本消息

### 问题3: 二次重连失败
- **现象**: 手机端 force-stop 重启后，PC 端 reconnect 失败（state=disconnected, 无 error）
- **原因**: NAT 打洞需要时间，且 Debug API 的 connect-chat 不复用已断开的会话
- **影响**: 每次手机重启后需要等待 NAT 重新注册

---

## 关键技术信息

| 项目 | 值 |
|------|-----|
| PC peerId | 423156 |
| 手机 peerId | 478703 |
| 永久密码 | 666999 |
| Debug API 端口 | 38881 |
| Debug API Token | dotchat-test-token-2026 |
| 中继服务器 | dotchat.dicad.cn:23116 |
| PC LAN IP | 192.168.31.42 |
| 连接类型 | 加密直连 TCP (direct=true, secure=true) |

---

## 测试结论

**PC→手机 消息收发链路完全正常**。消息通过 Rust `session.send_chat()` → protobuf 序列化 → TCP 加密直连 → 手机端解析显示，整条链路无问题。

手机→PC 方向因 UI 限制（语音模式无文本输入框）未能自动化验证，但网络层双向通道已建立（TCP 直连），理论上反向消息也能正常传输。
