# Troubleshooting: "ID does not exist" 排查指引

客户端提示 "ID does not exist" 时，根因是 **hbbs 信令服务器的在线 peer 表中查不到该 ID**。本文列出排查步骤。

## 一、确认被控端 ID 是否已登记

在 VPS 被控端 LUODA 日志中搜索以下关键字：

**成功的登记（ID 已进入在线表）**：
```
SEND RegisterPeer (ID registered in online table): id="xxx", server=dotchat.dicad.cn:21116, host=
```

**未登记的握手（仅握手，ID 未入表）**：
```
SEND RegisterPk (handshake only, ID NOT registered yet): host=, key_confirmed=false, host_key_confirmed=false
```

> **关键**：如果日志中只有 `RegisterPk` 没有 `RegisterPeer`，说明 `key_confirmed` 未设为 `true`，ID 从未登记到 hbbs。
> 常见原因：密钥验证未完成（PK mismatch、UDP 丢包）。

## 二、确认两端 rendezvous 服务器一致

客户端和改进端都必须连**同一个 hbbs**。检查两端的 `custom-rendezvous-server` 配置：

```bash
# 在 LUODA GUI 中: 设置 → 网络 → ID/中继服务器 → 自定义 rendezvous 服务器
# 应为: dotchat.dicad.cn
```

也可以在配置文件中直接查看：
- Windows: `%APPDATA%/luoda/_config/` 下的配置文件
- Linux: `~/.config/luoda/_config/` 下的配置文件

搜索关键字 `rendezvous-servers` 或 `custom-rendezvous-server`。

## 三、hbbs 在线表查询（服务端）

在 VPS 上进入 hbbs 容器/进程：

```bash
# 如果是 Docker 部署
docker exec -it <container_name> /hbbs -c list

# 或查看 hbbs 日志
docker logs <container_name> | grep "RegisterPeer\|online"
```

如果 hbbs 在线表中没有该 ID，回第一步确认被控端日志。

## 四、快速恢复方法

1. **在被控端重启 LUODA** — 重启会触发新的密钥握手和 ID 登记流程
2. **确认防火墙** — UDP 21116 端口双向可达（hbbs 握手走 UDP）
3. **检查密钥** — `RS_PUB_KEY` 必须匹配 hbbs 的 `id_ed25519.pub`。当前项目使用的公钥：
   ```
   OQnLEvt6xjfPCUc1ozpTUiAxijwnn624zy0GH9IxX90=
   ```

## 五、代码层面（客户端侧已改进）

- `src/rendezvous_mediator.rs` — `register_peer()` 增加诊断日志，明确区分握手和 ID 登记
- `src/rendezvous_mediator.rs` — 恢复重连间隔从 15s 缩短到 5s
- `src/client.rs` — `ID_NOT_EXIST` 错误信息附带服务器地址和自身 ID
