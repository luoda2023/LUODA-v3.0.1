# LUODA CI 构建监控总结

> v3.0.1 起 CI 已从 Gitee `luoda-full-build.yml` 迁移到 GitHub Actions，分散为 8 个 `build-*.yml` workflow。本文记录新流水线的监控方式。

## ✅ 已完成的配置

### 1. 自动触发配置

CI workflow 已配置为以下情况自动触发：

| 触发条件 | 配置 | 状态 |
|---------|------|------|
| `push` 到 `v3.0.1` 分支 | `.github/workflows/build-*.yml` (8 个) | ✅ |
| `workflow_dispatch` 手动触发 | GitHub Actions 标签页 / `gh workflow run` | ✅ |
| Release 上传 | `softprops/action-gh-release@v2` 上传到 `v3.0.1` 草稿 release | ✅ |

### 2. 监控工具

#### 方法 1: GitHub Actions Web 面板（推荐）

直接在浏览器访问：

```
https://github.com/luoda2023/LUODA-v3.0.1/actions
```

可查看每个 workflow 的运行状态、矩阵作业、实时日志、产物下载。

#### 方法 2: GitHub CLI（`gh`）

```bash
# 列出最近运行
gh run list --repo luoda2023/LUODA-v3.0.1 --limit 20

# 监控某次运行（实时刷新）
gh run watch <run-id> --repo luoda2023/LUODA-v3.0.1

# 查看失败运行的日志
gh run view <run-id> --repo luoda2023/LUODA-v3.0.1 --log-failed

# 手动触发某 workflow
gh workflow run build-exe.yml --repo luoda2023/LUODA-v3.0.1 --ref v3.0.1
```

#### 方法 3: 仓库内辅助脚本

| 脚本 | 用途 |
|------|------|
| `auto_build_and_test.py` | 本地调度 8 个 workflow、轮询状态并落盘日志 |
| `ci_auto_heal.py` | 解析失败日志，自动应用常见修复（编码、Cargo.lock 等） |
| `monitor.html` | 离线 HTML 面板，链接到 GitHub Actions（v3.0.1 已对齐） |

### 3. 构建配置

#### 8 个 workflow 一览

| Workflow | 产物 | 触发 |
|----------|------|------|
| `build-exe.yml` | `LUODA-3.0.1-portable-x64.exe`、`LUODA-3.0.1-Client-x64.exe` | push / dispatch |
| `build-msi.yml` | `LUODA-3.0.1-Setup.msi` | push / dispatch |
| `build-client-exe.yml` | 客户端 x64 EXE（与 `build-exe.yml` 协同） | push / dispatch |
| `build-sciter.yml` | `LUODA-3.0.1-portable-x86-sciter.exe` | push / dispatch |
| `build-apk.yml` | `LUODA-3.0.1-universal.apk` | push / dispatch |
| `build-deb.yml` | `LUODA-3.0.1.deb`、`LUODA-3.0.1.rpm` | push / dispatch |
| `build-dmg.yml` | `LUODA-3.0.1.dmg` | push / dispatch |
| `build-web.yml` | `LUODA-3.0.1-web.tar.gz` | push / dispatch |

#### 工具链版本（由 workflow `setup-*` 步骤固化）

- Rust 1.75（通过 `dtolnay/rust-toolchain`）
- Flutter 3.24（Web 兼容已恢复）
- Java 11（Android 构建）
- Node.js 16（Web 构建）

---

## 📊 监控方式对比

| 方式 | 优点 | 缺点 | 推荐场景 |
|------|------|------|---------|
| GitHub Actions Web | 官方界面、日志完整、可下载产物 | 需要浏览器 | 日常监控 |
| `gh` CLI | 可脚本化、可触发新运行 | 需要安装 `gh` | 自动化集成 |
| `auto_build_and_test.py` | 多 workflow 编排 + 自检 | 需要 `GH_TOKEN` | 本地全流程 |
| `ci_auto_heal.py` | 失败自动修复 | 依赖规则匹配 | 持续维护 |

---

## 🚀 使用指南

### 快速开始

1. **获取 GitHub Token**

   访问 `https://github.com/settings/tokens`，生成 PAT，勾选 `repo` 和 `workflow` 权限。

2. **设置环境变量**

   ```bash
   export GH_TOKEN=your_github_pat_here
   ```

3. **触发构建**

   - 方式 A（推荐）: `git push origin v3.0.1` 触发所有 8 个 workflow。
   - 方式 B: `gh workflow run build-exe.yml --ref v3.0.1` 单独触发。
   - 方式 C: 网页进入 `https://github.com/luoda2023/LUODA-v3.0.1/actions`，点击对应 workflow，选择 `Run workflow`。

4. **监控进度**

   - Web: `https://github.com/luoda2023/LUODA-v3.0.1/actions`
   - CLI: `gh run watch <run-id>`
   - 脚本: `python3 auto_build_and_test.py`

### 构建产物下载

构建成功后，产物会自动上传到 `v3.0.1` draft release：

```
https://github.com/luoda2023/LUODA-v3.0.1/releases
```

也可通过 workflow 运行页面的 Artifacts 区域下载临时存档。

---

## 🔧 故障排查

### 1. 构建不触发

- 确认推送的分支是 `v3.0.1`：`git rev-parse --abbrev-ref HEAD`
- 确认 8 个 workflow 文件都在 `.github/workflows/` 下且语法有效：`gh workflow list`
- 在 Actions 页面检查是否被 `matrix.arch` 条件或 `if` 表达式跳过。

### 2. Token 无效

```bash
# 检查 Token 是否设置
echo $GH_TOKEN
gh auth status
gh auth login --scopes repo,workflow
```

### 3. 构建失败

- 使用 `gh run view <run-id> --log-failed` 抓取失败日志。
- `ci_auto_heal.py` 会尝试匹配常见错误（编码、Cargo.lock、依赖缺失等）并自动提交修复。
- 跨平台失败时先看 runner 镜像（`runs-on:`）是否变化。

### 4. 产物找不到

- 在 release 页面查找 `LUODA-3.0.1-*` 命名资产。
- workflow 内部由 `Upload to v3.0.1 Release (...)` 步骤负责上传，被 `matrix.arch == 'x64'` 条件门控以避免重复上传。

---

## 📋 检查清单

构建前检查：

- [ ] 分支为 `v3.0.1` 或已创建 `v*` 标签
- [ ] `GH_TOKEN` 已设置，具备 `repo` 和 `workflow` 权限
- [ ] 8 个 `build-*.yml` workflow 在 `gh workflow list` 中显示 `active`
- [ ] 本地 `cargo check --all` 与 `flutter pub get` 通过

构建后验证：

- [ ] 8 个 workflow 全部 `success`
- [ ] Release `v3.0.1` 出现 `LUODA-3.0.1-*` 全部资产
- [ ] `LUODA-3.0.1-Setup.msi`、`LUODA-3.0.1-portable-x64.exe`、`LUODA-3.0.1-universal.apk`、`LUODA-3.0.1.deb`、`LUODA-3.0.1.rpm`、`LUODA-3.0.1.dmg`、`LUODA-3.0.1-web.tar.gz`、`LUODA-3.0.1-portable-x86-sciter.exe`、`LUODA-3.0.1-Client-x64.exe` 全部存在
- [ ] `CHANGELOG.md` 中的 Release Artifacts 表与实际上传资产一致

---

## 📞 支持资源

- `CI_GUIDE.md` - CI/CD 详细指南（v3.0.1 已对齐 GitHub Actions）
- `GITHUB_ACTIONS_GUIDE.md` - GitHub Actions 中文速查
- `docs/RELEASE.md` - 发布流程
- `BRANDING_SUMMARY.md` - 品牌化说明（包含官网 `dicad.cn`）
- `.github/workflows/build-*.yml` - 8 个 workflow 定义

---

**版本**: v3.0.1
**最后更新**: 2026-07-14