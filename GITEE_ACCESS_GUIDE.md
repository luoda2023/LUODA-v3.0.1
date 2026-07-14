# 📌 仓库访问说明（v3.0.1 起迁移到 GitHub）

> **历史背景**：v3.0.1 之前 LUODA 的镜像仓库位于 Gitee `https://gitee.com/soulemo_1/dicad`，受 Gitee Go 流水线 API 配额限制，CI 一直靠 Web 界面手动触发。v3.0.1 起主仓库正式迁移到 GitHub `https://github.com/luoda2023/LUODA-v3.0.1`，CI 改由 GitHub Actions 8 个 `build-*.yml` workflow 承担，本文件保留为历史访问说明。

---

## ✅ 当前仓库（v3.0.1+）

| 项 | 值 |
|----|----|
| 主仓库 | https://github.com/luoda2023/LUODA-v3.0.1 |
| Actions | https://github.com/luoda2023/LUODA-v3.0.1/actions |
| Release | https://github.com/luoda2023/LUODA-v3.0.1/releases |
| 默认构建分支 | `v3.0.1` |
| 触发方式 | `push` / `workflow_dispatch` / `gh workflow run` |

新流程请直接阅读：

- `GITHUB_ACTIONS_GUIDE.md` - GitHub Actions 中文速查
- `CI_GUIDE.md` - CI/CD 详细配置（v3.0.1 已对齐）
- `QUICK_START.md` - 触发与监控快速上手
- `MONITORING_SUMMARY.md` - 监控工具汇总
- `docs/RELEASE.md` - 发布流程

---

## 🗃️ 历史访问说明（Gitee 镜像，已弃用）

仅在使用旧 Gitee 镜像时参考以下内容。

### 1. 确认仓库访问权限

在浏览器打开：

```
https://gitee.com/soulemo_1/dicad
```

- **能正常访问** → 仓库存在，继续下一步。
- **不能访问** → 仓库未公开或没有访问权限，联系仓库管理员（`soulemo_1_0` / `LUODA`）开通权限。

### 2. 检查流水线功能

仓库页面顶部导航栏查看是否有 `流水线 / Pipelines / 构建 / Builds / DevOps` 选项卡。

- **有** → 进入并点击 `运行流水线`。
- **没有** → 该仓库未启用 Gitee Go（CI/CD），需要仓库管理员开通，或迁移到其他 CI（GitHub Actions / Jenkins / GitLab CI）。

### 3. 手动触发构建（如流水线可用）

1. 进入流水线页面
2. 点击 `运行流水线`
3. 选择 `luoda-full-build`
4. 分支选择 `v3.0.1`
5. 点击 `运行`

> 注意：Gitee `luoda-full-build.yml` 已不在 v3.0.1 主仓库中维护，仅作为 Gitee 镜像历史流水线存在。

---

## 📦 替代方案（已采用）

v3.0.1 起已切换到 GitHub Actions，无需再依赖 Gitee：

### 方案 A：本地构建

```bash
cd /workspace/LUODA-v3.0.1

# Rust 桌面端
cargo build --release

# Flutter 多端
cd flutter && flutter build apk     # Android
cd flutter && flutter build web     # Web
```

### 方案 B：GitHub Actions（推荐）

```bash
# 推送 v3.0.1 分支即触发 8 个 workflow
git push origin v3.0.1

# 手动触发单 workflow
gh workflow run build-exe.yml --ref v3.0.1
```

详细使用见 `GITHUB_ACTIONS_GUIDE.md` 与 `CI_GUIDE.md`。

---

## 📞 联系

仓库管理员：`soulemo_1_0` / `LUODA`（旧 Gitee 镜像），GitHub 端通过 Issues 联系 `luoda2023`。

---

## 📌 文件命名说明

本文件原名 `GITEE_ACCESS_GUIDE.md`，保留文件名以兼容旧文档交叉引用，但内容已统一为"v3.0.1 迁移到 GitHub 后的访问说明 + Gitee 历史镜像归档"。后续如需重命名为 `LEGACY_GITEE_MIRROR.md`，请同步更新 `README.md` / `CI_GUIDE.md` 等所有交叉引用。

---

**版本**: v3.0.1
**最后更新**: 2026-07-14