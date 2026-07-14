# LUODA CI/CD 构建指南

## 📋 自动触发配置

CI 流水线基于 GitHub Actions，已配置为自动触发。

### 触发条件
- ✅ `push` 到 `v3.0.1` 分支（构建 + Release 上传，受 `x64` matrix 门控避免重复）
- ✅ `workflow_dispatch` 手动触发（构建 + Release 上传）

### 支持的构建类型
- 🪟 **Windows**: EXE + MSI 安装包（含 portable / sciter）
- 🤖 **Android**: APK（universal / arm64-v8a / x86_64）
- 🐧 **Linux**: DEB 包 + 可执行文件
- 🍎 **macOS**: DMG
- 🌐 **Web**: Flutter Web 包
- 🎴 **Sciter**: x86 便携版（仅 `workflow_dispatch`）

---

## 🚀 手动触发流水线

### 方法 1: GitHub Actions 界面（推荐）

1. **访问 Actions 页面**
   ```
   https://github.com/luoda2023/LUODA-v3.0.1/actions
   ```

2. **选择对应 workflow**（左侧列表）
   - `Build LUODA Windows EXE` → `build-exe.yml`
   - `Build LUODA Windows MSI` → `build-msi.yml`
   - `Build LUODA Windows Client EXE` → `build-client-exe.yml`
   - `Build LUODA Android APK` → `build-apk.yml`
   - `Build LUODA Linux DEB` → `build-deb.yml`
   - `Build LUODA macOS DMG` → `build-dmg.yml`
   - `Build LUODA Web` → `build-web.yml`
   - `Build LUODA Sciter` → `build-sciter.yml`

3. **点击 "Run workflow" 按钮**

4. **选择分支** `v3.0.1`

5. **点击绿色 "Run workflow"** 开始构建

### 方法 2: GitHub CLI

```bash
# 安装 gh CLI: https://cli.github.com
gh auth login

# 触发某条 workflow
gh workflow run build-exe.yml --ref v3.0.1
gh workflow run build-msi.yml --ref v3.0.1
gh workflow run build-apk.yml  --ref v3.0.1
gh workflow run build-deb.yml  --ref v3.0.1
gh workflow run build-dmg.yml  --ref v3.0.1
gh workflow run build-web.yml  --ref v3.0.1
gh workflow run build-sciter.yml --ref v3.0.1

# 查看运行状态
gh run list --workflow=build-exe.yml --limit 5
gh run watch <run-id>
```

### 方法 3: 自动修复 + 监控

仓库内置 `ci_auto_heal.py` 引擎，可定期拉取最近一次 workflow 运行结果，匹配已知错误模式自动提交修复：

```bash
export GH_TOKEN=<your_personal_access_token>
python ci_auto_heal.py --once          # 跑一次扫描并尝试修复
python ci_auto_heal.py --loop 300      # 每 300 秒巡检一次
```

匹配规则涵盖：`Cargo.lock` 失效、Dart 非 UTF-8 字符、Rust 编译错误、Android AOM bindgen、Flutter pub 依赖、Web `chr()`/`getSettingsTabConfig` 等。

---

## 📊 监控构建进度

### Web 界面
```
https://github.com/luoda2023/LUODA-v3.0.1/actions
```
- 查看最新运行（按 workflow 过滤）
- 点击进入查看每个 job 的日志
- 失败步骤会标红，可直接下载完整日志

### 命令行
```bash
gh run list --limit 20
gh run view <run-id> --log-failed
```

### 构建产物位置（workflow 临时产物）
| 平台 | workflow 内产物路径 | 上传到 Release 的文件名 |
|------|---------------------|-----------------------|
| Windows Portable EXE | `SignOutput/LUODA-3.0.1-portable-x64.exe` | `LUODA-3.0.1-portable-x64.exe` |
| Windows Service EXE | `SignOutput/LUODA-3.0.1-service-x86.exe`（仅 x86 打包） | `LUODA-3.0.1-service-x86.exe` |
| Windows Naming EXE | `SignOutput/LUODA-3.0.1-naming-x86.exe` | `LUODA-3.0.1-naming-x86.exe` |
| Windows MSI | `res/msi/dist/LUODA-3.0.1-Setup.msi` | `LUODA-3.0.1-Setup.msi` |
| Windows Client EXE | `SignOutput/LUODA-3.0.1-Client-x64.exe` | `LUODA-3.0.1-Client-x64.exe` |
| Android APK | `flutter/build/app/outputs/dist-apk/LUODA-3.0.1-universal.apk` 等 | `LUODA-3.0.1-universal.apk` / `-arm64-v8a.apk` / `-x86_64.apk` |
| Linux DEB | `LUODA-3.0.1.deb` | `LUODA-3.0.1.deb` |
| Linux RPM | `LUODA-3.0.1.rpm` | `LUODA-3.0.1.rpm` |
| macOS DMG | `LUODA-3.0.1.dmg` | `LUODA-3.0.1.dmg` |
| Web | `flutter/build/LUODA-3.0.1-web.tar.gz` | `LUODA-3.0.1-web.tar.gz` |
| Sciter | `SignOutput/LUODA-3.0.1-portable-x86-sciter.exe` | `LUODA-3.0.1-portable-x86-sciter.exe` |

---

## 🔧 构建配置说明

### Workflows（`.github/workflows/`）
- `build-exe.yml` — Windows Portable / Client / Service / Naming EXE（matrix: x86 + x64）
- `build-msi.yml` — Windows MSI 安装包
- `build-client-exe.yml` — Windows Client 独立构建（matrix: x86 + x64）
- `build-apk.yml` — Android APK（matrix: universal / arm64-v8a / x86_64）
- `build-deb.yml` — Linux DEB / RPM（matrix: deb + rpm）
- `build-dmg.yml` — macOS DMG
- `build-web.yml` — Flutter Web 包
- `build-sciter.yml` — Sciter x86 便携版（`workflow_dispatch` only）

### Release 上传门控
所有 8 个 workflow 使用 `softprops/action-gh-release@v2` 上传到 `v3.0.1` 草稿 Release：

```yaml
if: github.event_name == 'workflow_dispatch' || github.event_name == 'push'
```

`build-exe.yml` 和 `build-client-exe.yml` 因为 matrix 含 `x86`，额外加 `matrix.arch == 'x64'` 防 x86 行重复上传：

```yaml
if: matrix.arch == 'x64' && (github.event_name == 'workflow_dispatch' || github.event_name == 'push')
```

### 本地构建依赖
- Rust toolchain ≥ `1.75.x`（推荐 `rustup default stable`）
- Flutter ≥ `3.16.x`，Dart SDK 与之配套
- Windows：Visual Studio 2022 Build Tools + MSBuild + WiX v4.0.5（MSI 用）
- Linux：`libgtk-3-dev libxcb-randr0-dev ...` + `pkg-config`
- macOS：Xcode 14+ + CocoaPods
- Android：Android Studio + NDK + `flutter doctor --android-licenses`

---

## 🐛 故障排查

### 常见原因

1. **依赖缺失**
   ```bash
   flutter --version       # 应 3.16.x 以上
   rustc  --version        # 应 1.75.x 以上
   cargo  --version
   ```

2. **`Cargo.lock` 失效**
   CI 会自动 `cargo generate-lockfile`；本地可手动：
   ```bash
   cargo generate-lockfile
   ```

3. **Android AOM bindgen 失败**
   设置环境变量：
   ```bash
   export AOM_INCLUDE_PATH="$PWD/libs/aom"
   export BINDGEN_EXTRA_CLANG_ARGS=""
   cargo build --target aarch64-linux-android --features flutter -p scrap
   ```

4. **Dart 非 UTF-8 字符错误**
   CI 自动替换以下字符为 ASCII：`–—''""   `。本地可：
   ```bash
   python ci_auto_heal.py --once
   ```

5. **MSI preprocess 找不到版本号**
   `res/msi/preprocess.py` 在未传 `--version` 时会回退到 `cargo run -- --version` 输出，匹配正则 `v?(\d+\.\d+\.\d+)`。确保 `src/version.rs` 中 `VERSION` 是 `X.Y.Z` 三段格式。

### 本地复现构建
```bash
# Windows EXE
cargo build --release

# Android APK
cd flutter && flutter build apk --release

# Linux DEB
cargo build --release  # 或 cargo deb

# Web
cd flutter && flutter build web --release
```

---

## 📱 下载构建产物

### 方式 1: GitHub Release
```
https://github.com/luoda2023/LUODA-v3.0.1/releases/tag/v3.0.1
```

### 方式 2: GitHub Actions Artifacts（每次运行的临时产物）
```bash
gh run download <run-id> -n <artifact-name>
```

### 方式 3: 直接 wget（Release 公开后）
```bash
wget https://github.com/luoda2023/LUODA-v3.0.1/releases/download/v3.0.1/LUODA-3.0.1-portable-x64.exe
wget https://github.com/luoda2023/LUODA-v3.0.1/releases/download/v3.0.1/LUODA-3.0.1-Setup.msi
wget https://github.com/luoda2023/LUODA-v3.0.1/releases/download/v3.0.1/LUODA-3.0.1-universal.apk
wget https://github.com/luoda2023/LUODA-v3.0.1/releases/download/v3.0.1/LUODA-3.0.1.deb
```

---

## ⚙️ 自定义构建

### 修改版本号
- `src/version.rs` 的 `VERSION` 常量
- `Cargo.toml` 的 `[package].version`
- `flutter/pubspec.yaml` 的 `version: 3.0.1+1`
- `res/luoda-setup.iss` 的 `#define MyAppVersion "3.0.1"`
- `flutter/windows/runner/Runner.rc` 的 `VERSION_AS_STRING "3.0.1"`
- `libs/portable/Cargo.toml` 的 `[package].version`
- MSI 版本号由 `res/msi/preprocess.py` 动态注入，无需手动改

更多版本同步细节见 `docs/RELEASE.md`。

### 添加新构建目标
在 `.github/workflows/` 新增 `build-<target>.yml`，并同步注册到 `ci_auto_heal.py` 的 `BUILD_TARGETS` 列表，使其受自动修复覆盖。

### 配置自动发布
确认 workflow 内的 `softprops/action-gh-release@v2` 步骤满足：
- `tag_name: v3.0.1`
- `draft: true`（草稿状态，待人工校验后公开）
- `files:LUODA-3.0.1-*`（与产物命名一致）

---

## 📞 支持

- workflow 配置问题：查看 `.github/workflows/` 中各 yaml
- 构建产物发布问题：查看 `docs/RELEASE.md`
- 自动修复引擎：查看 `ci_auto_heal.py`
- 通用构建主流程：查看 `BRANDING_SUMMARY.md` / `README.md`


## 🔐 凭据与本地脚本约束

仓库不接受硬编码 GitHub Personal Access Token。所有需要 PAT 的本地辅助脚本（`monitor_builds.ps1`、`publish_release.ps1`、`monitor-ci.sh`、`ci_auto_heal.py` 等）一律改为从环境变量 `GH_TOKEN` 读取，且脚本启动时必须校验其存在，缺失则报错退出，例如：

```powershell
$token = $env:GH_TOKEN
if (-not $token) { Write-Error "GH_TOKEN env var is required (GitHub PAT)"; exit 1 }
```

```bash
GH_TOKEN="${GH_TOKEN:-}"
if [ -z "$GH_TOKEN" ]; then echo "请设置 GH_TOKEN"; exit 1; fi
```

```python
TOKEN = os.environ.get("GH_TOKEN") or ""
if not TOKEN: raise SystemExit("GH_TOKEN env var is required")
```

设置 PAT 的本地持久化方法（任选其一，**不要写入仓库文件**）：

- 当前 PowerShell 会话：`$env:GH_TOKEN = "ghp_xxx..."`
- 用户级（推荐，跨会话生效，不会进 git）：
  `[Environment]::SetEnvironmentVariable("GH_TOKEN", "ghp_xxx...", "User")`
- GitHub Actions 中：通过仓库 Settings → Secrets and variables → Actions 配置 `GH_TOKEN` secret，workflow 里以 `${{ secrets.GH_TOKEN }}` 引用。

本地辅助脚本（`monitor_builds.ps1`、`publish_release.ps1`、`.build_status.*`、`failed-dmg-logs.zip` 等）已通过 `.gitignore` 排除，避免 IDE 索引或备份误传到远端。
---

**最后更新**: 2026-07-14
**版本**: v3.0.1
