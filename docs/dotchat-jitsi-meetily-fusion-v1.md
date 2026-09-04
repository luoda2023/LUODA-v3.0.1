# 点聊 × Jitsi × Meetily 融合设计（v1）

> 目标：把开源视频会议（Jitsi）的多人音视频能力 + 会议纪要（Meetily 引擎）
> 充分融入点聊(DotChat)，形成"能开会、能纪要、能远程协助、能演示文件/操作"的全新软件。
> 状态：设计草案，待用户确认后进入实施。

## 1. 背景与现状（核实于代码）

| 能力 | 现状 | 本质 | 融合处置 |
|---|---|---|---|
| 远程协助 | `connect()` 1v1 操控 + viewer 只读观摩(≤8人/举手/踢人) | 自有 P2P 屏幕通道 | **保留**（核心资产） |
| 语音电话 | `voice_call_audio.dart` record→Opus→自有 P2P 隧道(FFI) | 1v1 呼叫 | **保留为"呼叫"**，与会议互斥 |
| 会议 tab | `mobile/pages/remote_meeting_page.dart`(1107行) + `meeting_group_panel.dart`；MeetingGroup(meetingId/host/presenter/viewerToken/inviteShortCode) | 无服务器 P2P **屏幕共享观摩群，无多方实时音视频** | **入口保留**，媒体层升级为 Jitsi |
| 摄像头查看 | Client Type `camera`（远程看对方设备摄像头） | 监控语义 | **保留不混用** |
| 文件传输/聊天 | P2P 直连 + SQLite 持久化 | IM | **保留** |
| 会议纪要 | 无 | — | **新增**(Meetily) |

结论：点聊从未有"多方实时音视频会议"。融合=补齐媒体层，不是推倒重来。

## 2. 目标形态（全新软件）

```
┌──────────── 点聊 DotChat (Rust+Flutter) ────────────┐
│ 聊天 | 联系人 | 远程协助(操控+观摩) | 文件 | 摄像头查看 │
│        会议 tab ─ 会议群(meeting group)                │
│   ├─ 移动端: jitsi_meet_flutter_sdk (官方原生 SDK)     │
│   ├─ 桌面端: WebView(WebView2/CEF) + Jitsi iframe      │
│   └─ 纪要: 录 Jitsi 音频 → whisper/parakeet → LLM 摘要  │
└───────────────┬───────────────────────────────────────┘
  房间映射: meetingId/inviteShortCode → Jitsi room(JWT 鉴权)
┌───────────────▼───────────────────────────────────────┐
│ docker-jitsi-meet 自建: Prosody + Jicofo + JVB(SFU)    │
│   + coturn(TURN) + Jibri(可选录制)                     │
└───────────────────────────────────────────────────────┘
```

分工原则：
- **会内音视频/摄像头/屏幕共享** = Jitsi（WebRTC SFU，多人高质量）
- **文件/操作演示、"替别人操控"** = 现有远程协助（其窗口可作为 Jitsi 屏幕共享源）
- **聊天/群管理/联系人** = 点聊（会外持久；会内即时聊天用 Jitsi）
- **纪要/转写** = Meetily 引擎（whisper/parakeet + SQLite + Ollama/LLM）

## 3. 技术选型（路线 B，推荐）

| 路线 | 结论 |
|---|---|
| A 自研多人 SFU | 否决：12–24 人月，质量无法对标 Jitsi |
| **B 自建 Jitsi + 嵌入点聊** | **采纳**：MVP 1–2 月，媒体层生产级 |
| C 特性清单逐项自研 | 否决：=A 渐进版，重复踩坑 |

客户端嵌入：
- 移动端：官方 `jitsi_meet_flutter_sdk`（13.1.1, 2026-08 活跃维护；Android minSdk24/iOS15.1+）
- 桌面端：WebView2 + Jitsi External API iframe（jitsi-meet-electron 同思路）
- **弃用**停更社区包 `jitsi_meet`/`jitsi_meet_plus`/`jitsi_meet_web`(2020–21)

## 4. "删旧"决策（取最优删旧的）

**保留**：远程协助(操控+viewer)、点对点聊天/群聊、文件传输、摄像头查看、1v1 语音电话(呼叫语义+无服务器可用)。
**替换**：meeting group 旧"观摩式会议"媒体层 → Jitsi 多人音视频；会内聊天用 Jitsi，点聊群聊保留为会外持久。
**结构复用**：邀请链接/成员/权限模型保留（映射 JWT moderator/participant）。
**互斥规则**：voice_call 与入会互斥（避免麦克风/扬声器抢占）。

## 5. 里程碑

### 阶段一 MVP（4–6 周）
1. 部署 docker-jitsi-meet（公网机 + 域名 SSL + coturn）
2. 点聊"即时开会"：会议群卡片 → 生成 Jitsi 房间 → 移动端 SDK / 桌面 WebView join
3. 会内音视频/摄像头/屏幕共享/Jitsi 聊天；远程控制窗口可作共享源
4. 验证：4 端(2桌面+2手机)同房间，音画<500ms；LAN+公网各跑通

### 阶段二 增强（4–6 周）
1. JWT 鉴权对齐 host/presenter/member 权限，踢人/举手双向
2. 纪要 MVP：主持人本地录 → 会后离线转写+摘要 → 纪要卡片回写聊天
3. 邀请链接统一（一个短码：能控进点聊，否则进 Jitsi/viewer）
4. Jibri 录制可选，录制文件经文件通道回传

### 阶段三 完整（6–10 周）
1. 纪要 bot 常驻（audio-only 入会、实时字幕、结构化纪要）
2. 预定会议 + 历史会议检索
3. 虚拟背景/投票/分组讨论(开关启用)
4. 无 Jitsi 服务器降级路径保留(LAN 老式观摩会)

## 6. 风险与对策

| 风险 | 对策 |
|---|---|
| 双网络基础设施(点聊中继 vs Jitsi TURN) | coturn 合并到 Jitsi 服务器；带宽分开预算 |
| 国内跨网 UDP 差 | 默认 TURN TCP 443 兜底 |
| SFU 服务器成本 | 8C16G ≈ 2–3 场 10 人会；按需扩容 |
| 桌面 WebView 与点聊 UI 割裂/设备抢占 | 媒体管家先抢再放；WebView2 固定 profile |
| 移动端后台保活(厂商杀进程) | 前台服务+通知渠道合并，电池白名单 |
| E2EE 与纪要/录制互斥 | 会议类型开关："隐私模式"禁录禁纪要 |
| 纪要转写算力 | MVP 会后转写；bot 服务器 GPU/ONNX 小模型 |

## 7. 源码整洁要求
- 旧媒体层代码：确认被替换后，用 git rm 删除，不保留死代码
- Jitsi 侧只做"映射/嵌入/纪要/并行轨道"薄层，避免深入改 Prosody
- Meetily 只搬 Rust 引擎(whisper/parakeet/SQLite schema)，Next.js UI 不搬，重写为 Flutter
