# 🚀 LUODA CI 构建快速启动指南

> v3.0.1 起 CI 已迁移到 GitHub Actions，分散为 8 个 `.github/workflows/build-*.yml` workflow。本文是触发与监控的简明手册。

---

## 📋 步骤 1：触发构建

CI 在以下情况自动触发：

- `git push origin v3.0.1`（推送代码到 `v3.0.1` 分支）
- 网页进入 `https://github.com/luoda2023/LUODA-v3.0.1/actions`，选择目标 workflow，点击 `Run workflow`。
- `gh workflow run build-<name>.yml --ref v3.0.1`（CLI 触发）

### 8 个 workflow

| Workflow | 产物 |
|----------|------|
| `build-exe.yml` | `LUODA-3.0.1-portable-x64.exe`、`LUODA-3.0.1-Client-x64.exe` |
| `build-msi.yml` | `LUODA-3.0.1-Setup.msi` |
| `build-client-exe.yml` | `LUODA-3.0.1-Client-x64.exe`（与 `build-exe.yml` 协同） |
| `build-sciter.yml` | `LUODA-3.0.1-portable-x86-sciter.exe` |
| `build-apk.yml` | `LUODA-3.0.1-universal.apk` |
| `build-deb.yml` | `LUODA-3.0.1.deb`、`LUODA-3.0.1.rpm` |
| `build-dmg.yml` | `LUODA-3.0.1.dmg` |
| `build-web.yml` | `LUODA-3.0.1-web.tar.gz` |

---

## 📊 步骤 2：监控构建进度

### 方法 A：GitHub Actions 网页面板（推荐）

访问 `https://github.com/luoda2023/LUODA-v3.0.1/actions`，点击任意 workflow 查看实时日志和矩阵作业状态。

### 方法 B：GitHub CLI

```bash
# 列出最近 20 次运行
gh run list --repo luoda2023/LUODA-v3.0.1 --limit 20

# 实时跟踪某次运行
gh run watch <run-id> --repo luoda2023/LUODA-v3.0.1

# 查看失败日志
gh run view <run-id> --repo luoda2023/LUODA-v3.0.1 --log-failed
```

### 方法 C：本地辅助脚本

```bash
# 编排 8 个 workflow 的本地全流程
export GH_TOKEN=your_github_pat
python3 auto_build_and_test.py

# 仅抓取并解析失败日志，尝试自动修复
python3 ci_auto_heal.py
```

---

## ⏱️ 预计构建时间

| Workflow | 预计时间 | 产物 |
|----------|---------|------|
| `build-exe.yml` | 15-30 分钟 | Portable / Client x64 EXE |
| `build-msi.yml` | 8-15 分钟 | MSI 安装包 |
| `build-client-exe.yml` | 15-30 分钟 | Client x64 EXE |
| `build-sciter.yml` | 10-20 分钟 | Sciter x86 便携版 |
| `build-apk.yml` | 10-20 分钟 | universal APK |
| `build-deb.yml` | 10-15 分钟 | DEB + RPM |
| `build-dmg.yml` | 10-20 分钟 | macOS DMG |
| `build-web.yml` | 3-8 分钟 | Flutter Web 包 |
| **总计（并行）** | **40-90 分钟** | 全部产物 |

---

## 📦 构建产物下载

构建成功后，所有产物自动上传到 `v3.0.1` draft release：

```
https://github.com/luoda2023/LUODA-v3.0.1/releases
```

也可在 workflow 运行页面的 `Artifacts` 区域下载临时存档（保留 90 天）。

---

## 🔧 常见错误处理

### 错误 1：workflow 不触发

- 确认推送分支是 `v3.0.1`：`git rev-parse --abbrev-ref HEAD`
- 确认 workflow 文件位于 `.github/workflows/` 下且 YAML 语法有效
- 在 Actions 页面检查是否被 `matrix.arch == 'x64'` 等条件门控跳过

### 错误 2：构建失败

- 在 Actions 页面点击失败运行查看实时日志
- CLI：`gh run view <run-id> --log-failed`
- 触发 `ci_auto_heal.py` 自动修复常见问题（编码 / Cargo.lock / 缺失依赖）

### 错误 3：Token 失效

```bash
gh auth status
gh auth login --scopes repo,workflow
```

### 错误 4：产物未上传到 release

- 检查 `Upload to v3.0.1 Release (...)` 步骤是否被 `if: matrix.arch == 'x64' && ...` 条件跳过
- 确认 `softprops/action-gh-release@v2` 接收到 `tag_name: v3.0.1`

---

## 📞 实时监控辅助

`auto_build_and_test.py` 提供以下能力：

1. **8 workflow 编排**：依次触发 5 个矩阵构建，等待完成。
2. **状态轮询**：每 30 秒拉取一次 run 状态。
3. **失败自检**：调用 `ci_auto_heal.py` 尝试自动修复。
4. **日志落盘**：每次运行的日志写入 `.auto_build_logs/`。

---

## 🎯 快速操作清单

### 出发前检查

- [ ] 已登录 GitHub 账号且能访问 `luoda2023/LUODA-v3.0.1`
- [ ] `GH_TOKEN` 已设置并具备 `repo`、`workflow` 权限
- [ ] 知道如何触发 / 监控 workflow

### 触发构建

- [ ] 推送：`git push origin v3.0.1`
- [ ] 或网页触发：进入 `https://github.com/luoda2023/LUODA-v3.0.1/actions`
- [ ] 或 CLI 触发：`gh workflow run build-exe.yml --ref v3.0.1`

### 监控构建

- [ ] Actions 页面查看运行列表
- [ ] 或 `gh run watch <run-id> --repo luoda2023/LUODA-v3.0.1`
- [ ] 或运行 `python3 auto_build_and_test.py`

### 构建完成后

- [ ] 8 个 workflow 全部 `success`
- [ ] Release `v3.0.1` 出现全部 `LUODA-3.0.1-*` 资产
- [ ] 下载并测试各平台产物

---

## 📖 相关文档

| 文档 | 说明 |
|------|------|
| `CI_GUIDE.md` | CI/CD 详细配置指南 |
| `GITHUB_ACTIONS_GUIDE.md` | GitHub Actions 中文速查 |
| `MONITORING_SUMMARY.md` | 监控工具使用指南 |
| `docs/RELEASE.md` | 发布流程 |
| `BRANDING_SUMMARY.md` | 品牌化说明（官网 `dicad.cn`） |

---

## 🔗 快速链接

- **Actions 页面**：https://github.com/luoda2023/LUODA-v3.0.1/actions
- **代码仓库**：https://github.com/luoda2023/LUODA-v3.0.1
- **Release**：https://github.com/luoda2023/LUODA-v3.0.1/releases
- **GitHub CLI 文档**：https://cli.github.com/manual/

---

**准备就绪！推送到 `v3.0.1` 即可触发构建。🚀**