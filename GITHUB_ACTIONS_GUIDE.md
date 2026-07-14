# 🚀 GitHub Actions 自动构建指南

## ⚠️ 重要安全提示

**请立即撤销你之前暴露的 Token！**

1. 访问：https://github.com/settings/tokens
2. 删除已泄露的 Token
3. 生成新 Token（权限：`repo`, `workflow`）
4. 保存新 Token，不要告诉任何人

---

## 📋 快速开始

### 步骤 1：生成 GitHub Token

1. 访问：https://github.com/settings/tokens/new
2. 填写备注（如：LUODA CI）
3. 勾选权限：
   - ✅ `repo` (完整控制私有仓库)
   - ✅ `workflow` (管理 GitHub Actions)
4. 点击「Generate token」
5. **复制 Token 并保存**（只会显示一次）

### 步骤 2：创建 GitHub 仓库

1. 访问：https://github.com/new
2. 仓库名称：`LUODA-v3.0.1`
3. 可见性：Public 或 Private（都行，都免费）
4. **不要**初始化 README/.gitignore
5. 点击「Create repository」

### 步骤 3：推送代码

```bash
cd /workspace/LUODA-v3.0.1

# 添加 GitHub 远程仓库
git remote add github https://github.com/luoda2023/LUODA-v3.0.1.git

# 推送代码
git push github v3.0.1
```

### 步骤 4：自动构建开始！

推送后，GitHub Actions 会自动触发构建。

查看构建状态：
```
https://github.com/luoda2023/LUODA-v3.0.1/actions
```

---

## 🛠️ 使用监控工具

### 触发构建

```bash
# 替换 YOUR_TOKEN 为你的 Token
python3 trigger-github-build.py --token YOUR_TOKEN

# 只构建 Windows
python3 trigger-github-build.py --token YOUR_TOKEN --type windows

# 只构建 Android
python3 trigger-github-build.py --token YOUR_TOKEN --type android
```

### 监控构建

```bash
# 自动监控最近的构建
python3 monitor-github-build.py --token YOUR_TOKEN

# 监控指定的构建 ID
python3 monitor-github-build.py --token YOUR_TOKEN --run-id 12345678
```

### 分析错误

```bash
# 分析最近的失败构建
python3 auto-fix-github-build.py --token YOUR_TOKEN
```

---

## 📊 构建产物下载

构建成功后，下载产物：

1. 访问构建页面：https://github.com/luoda2023/LUODA-v3.0.1/actions
2. 点击成功的构建（绿色✅）
3. 滚动到页面底部
4. 点击「Artifacts」下载：
   - `luoda-windows-exe` - Windows 可执行文件
   - `luoda-windows-dlls` - Windows DLL 依赖
   - `luoda-android-apk` - Android APK
   - `luoda-linux-binary` - Linux 可执行文件
   - `luoda-linux-deb` - Linux DEB 包

---

## 🔧 自动触发配置

### 推送触发

以下操作会自动触发构建：

| 操作 | 触发构建 |
|------|---------|
| `git push origin v3.0.1` | ✅ 全平台构建 |
| `git push origin <branch>` | ❌ 不触发 |
| `git tag v3.0.1 && git push origin v3.0.1` | ✅ 全平台构建 + 创建 Release |
| 创建 Pull Request 到 v3.0.1 | ✅ 全平台构建（测试） |

### 手动触发

使用 Web 界面或 API：

**Web 界面**：
1. 访问：https://github.com/luoda2023/LUODA-v3.0.1/actions
2. 点击左侧「LUODA Full Build」
3. 点击「Run workflow」
4. 选择分支和构建类型
5. 点击「Run workflow」

**API 触发**：
```bash
python3 trigger-github-build.py --token YOUR_TOKEN
```

---

## ⏱️ 预计构建时间

| 平台 | 预计时间 | 产物 |
|------|---------|------|
| Windows | 10-20 分钟 | EXE + DLL |
| Android | 15-30 分钟 | APK |
| Linux | 10-20 分钟 | Binary + DEB |
| **总计** | **30-60 分钟** | 全部产物 |

---

## 🔐 安全最佳实践

### ✅ 正确做法

1. **使用 GitHub Secrets**
   ```yaml
   env:
     MY_TOKEN: ${{ secrets.MY_TOKEN }}
   ```

2. **最小权限原则**
   - 只授予必要的权限
   - 定期轮换 Token

3. **不要在代码中硬编码 Token**
   ```bash
   # ❌ 错误
   GITHUB_TOKEN = "ghp_xxxxx"
   
   # ✅ 正确
   GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN")
   ```

### ❌ 错误做法

- 将 Token 提交到代码仓库
- 在聊天中发送 Token
- 使用明文存储 Token

---

## 📞 常见问题

### Q: 构建失败怎么办？

A: 运行错误分析工具：
```bash
python3 auto-fix-github-build.py --token YOUR_TOKEN
```

### Q: 如何取消正在运行的构建？

A: 访问构建页面，点击「Cancel workflow」

### Q: 免费额度是多少？

A: GitHub Actions 提供 2000 分钟/月免费额度（Public 仓库无限免费）

### Q: 如何查看构建历史？

A: 访问：https://github.com/luoda2023/LUODA-v3.0.1/actions

---

## 📁 文件说明（实际仓库现状）

| 文件 | 说明 |
|------|------|
| `.github/workflows/build-*.yml` | 各平台构建 workflow：`build-exe.yml`、`build-msi.yml`、`build-apk.yml`、`build-deb.yml`、`build-dmg.yml`、`build-web.yml` |
| `auto_build_and_test.py` | 触发并轮询 dispatch 构建、汇总产物 |
| `monitor_builds.ps1` / `monitor-ci.sh` | 本地监控 dispatch 构建进度与 release 资产 |
| `publish_release.ps1` | 本地发布 release 资产 |
| `ci_auto_heal.py` | 自动分析构建日志并尝试修复 |
| `push-changes.sh` | 推送 `v3.0.1` 到远端并触发官方 push 触发式 workflow |
| `Dockerfile` / `entrypoint.sh` | Linux/macOS 构建容器镜像入口 |
| `CI_GUIDE.md` | CI 配置与凭据安全约束（权威） |
| `GITHUB_ACTIONS_GUIDE.md` | 本指南 |

> 早期版本提到的 `trigger-github-build.py`、`monitor-github-build.py`、`auto-fix-github-build.py`、`.github/workflows/build.yml` 已重构为上述分平台结构与命名，不再存在。

---

## 🎯 下一步

1. **生成 GitHub PAT**（Settings → Developer settings → Personal access tokens）并赋权 `repo`、`workflow`
2. **以环境变量方式注入**：`[Environment]::SetEnvironmentVariable("GH_TOKEN","ghp_xxx...","User")`（持久但**不入仓库**）或 `$env:GH_TOKEN="ghp_xxx..."`（仅当前会话）
3. **GitHub Actions 中**：在仓库 Settings → Secrets and variables → Actions 新建 `GH_TOKEN` secret，workflow 内用 `${{ secrets.GH_TOKEN }}` 引用
4. 推送 `v3.0.1` 分支，CI 自动构建（详见 `push-changes.sh`、`auto_build_and_test.py`）
5. 等待 `monitor_builds.ps1` 或 Actions 页面显示全部 completed
6. 在 release 页下载 `LUODA-3.0.1-*` 产物并人工校验

详细凭据约束与脚本清单见 `CI_GUIDE.md` 末尾"🔐 凭据与本地脚本约束"段。
