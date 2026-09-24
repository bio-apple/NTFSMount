# 分发状态 · Distribution status

**当前公开渠道仅限 GitHub pre-release，供个人使用；在取得 FUSE-T 书面许可并公证之前，这不是可再分发的产品。**

直发应用，不上 Mac App Store。仅支持 Apple Silicon（M 芯片）与 macOS 13.0+，**不支持 Intel Mac（x86_64）**；构建为 arm64，不要做 Intel / 通用二进制。下面两项在打正式对外包之前必须完成；未完成时只宜个人使用或标成预发布。

## 1. Apple 公证 · Notarization

需要付费 Apple Developer Program 的 **Developer ID Application** 证书，以及 `notarytool` 凭据。本仓库打的是 `.app` + DMG，**不用 Developer ID Installer**（没有安装 pkg）。

```bash
CODESIGN_IDENTITY='Developer ID Application: Name (TEAM)' \
NOTARY_PROFILE='notarytool-profile' \
./scripts/package-dmg.sh
```

`scripts/notarize.sh` 会对应用与内嵌二进制做 Hardened Runtime 签名、提交公证并 staple。未设置证书时构建为 ad-hoc：Gatekeeper 会拦截。

### 未公证构建如何打开（Gatekeeper）

与首次启动文案、README、`OnboardingCopy` 一致：

1. **按住 Control 点应用 → 打开**（或右键 → 打开），在对话框里确认打开。
2. 或打开 **系统设置 → 隐私与安全性**，在被拦记录处点 **仍要打开**。
3. 仍被隔离时，终端执行（与应用内提示相同）：
   ```bash
   xattr -d com.apple.quarantine /Applications/NTFSMount.app
   ```
   若整个包仍带隔离属性，可用递归：
   ```bash
   xattr -dr com.apple.quarantine /Applications/NTFSMount.app
   ```
   然后再次打开。自己用可以继续；作为产品发给别人请先公证。

### 本机公证凭据

`scripts/notarize.sh` 认下面任一路径（有证书才会提交；缺一则跳过公证，仍可能是 ad-hoc / 仅签名）：

| 变量 | 用途 |
| --- | --- |
| `CODESIGN_IDENTITY` | Developer ID Application 身份，例如 `Developer ID Application: Name (TEAM)`。未设则 ad-hoc（Gatekeeper 拦截） |
| `NOTARY_PROFILE` | 本机钥匙串里的 `notarytool` profile（`xcrun notarytool store-credentials`） |
| `APPLE_API_KEY_ID` | App Store Connect API Key ID |
| `APPLE_API_ISSUER` | Issuer ID（UUID） |
| `APPLE_API_KEY` | AuthKey_*.p8 **全文** |
| `APPLE_API_KEY_PATH` | 可选。已有 .p8 文件路径；设置后不必再设 `APPLE_API_KEY` |

`NOTARY_PROFILE` 与 `APPLE_API_KEY_ID` + `APPLE_API_ISSUER` + (`APPLE_API_KEY` 或 `APPLE_API_KEY_PATH`) 二选一即可。

### CI（GitHub Actions）

`.github/workflows/build.yml`：push 到 `main` 与 PR 会跑 SwiftLint / UnitTest / Security Scan / Build；`main` 上另打 `.app` 工件。推送 `v*` tag 时打 DMG 并创建 GitHub Release。**不要在真盘 workflow 里公证**；`.github/workflows/manual-disk-test.yml` 不读这些 secrets。

公证在 Actions 上不能用本机钥匙串 `NOTARY_PROFILE`。请在仓库 **Settings → Secrets and variables → Actions** 配置。`scripts/ci-import-signing.sh` 导入 .p12；`scripts/notarize.sh` 用 API Key 提交：

| Secret / 变量 | 用途 |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | Developer ID Application 的 .p12，`base64` 后的全文。缺则 CI 跳过导入，走 ad-hoc |
| `APPLE_CERTIFICATE_PASSWORD` | 该 .p12 的密码（有证书时必填） |
| `CODESIGN_IDENTITY` | 可选。例如 `Developer ID Application: Name (TEAM)`；省略则用 p12 里第一张 Developer ID Application |
| `APPLE_API_KEY_ID` | App Store Connect API Key ID |
| `APPLE_API_ISSUER` | Issuer ID（UUID） |
| `APPLE_API_KEY` | AuthKey_*.p8 全文 |
| `NOTARY_PROFILE` | 可选。Actions 上通常无效（没有你的钥匙串 profile）；本机打包才用 |
| `FUSE_T_REDISTRIBUTION_OK` | **仓库变量**（`vars.`，不是 secret）。仅在已公证 **且** 已有 FUSE-T 书面许可时设为 `1`，Release 才可当 Latest |

本机仍可用 `NOTARY_PROFILE`。证书与 API Key 齐了才会 `notarytool submit`；缺一则仍发布 **pre-release**（未公证）。只有公证成功 **且** 仓库变量 `FUSE_T_REDISTRIBUTION_OK=1` 时才创建非预发布（可成为 Latest）。未取得 FUSE-T 书面许可不要设该变量。公开 Latest 必须同时：已公证 **并且** FUSE-T 许可证允许再分发。

```bash
git tag v0.1.0
git push origin v0.1.0
```

## 2. FUSE-T `go-nfsv4`

捆绑的 `go-nfsv4` **不是 GPL**。FUSE-T 写明个人使用免费；作为产品嵌入或分发可能需要商业许可。钉死 **FUSE-T 1.2.7**（`scripts/prepare-runtime.sh` 的 `FUSE_T_VERSION` 与 [runtime/versions.txt](../runtime/versions.txt)）；Package.swift 无法钉 macOS pkg。

- 联系：https://www.fuse-t.org/
- 取得书面授权后：`FUSE_T_REDISTRIBUTION_OK=1 ./scripts/package-dmg.sh`，并把本文件此节改为「已授权」。
- 未设置该变量时，DMG 带「个人使用说明」，GitHub Release **必须**标为 pre-release；**不要**把该包当作 GitHub Latest，也禁止第三方镜像。
- **公开 Latest 仅当已公证并且 FUSE-T 许可证允许再分发**（仓库变量 `vars.FUSE_T_REDISTRIBUTION_OK=1`）。缺一不可。
- 正式对外下载页必须同时完成 Developer ID 公证与 FUSE-T 书面授权。许可证拆分见仓库根目录 [NOTICE](../NOTICE)。

macFUSE 依赖内核扩展，本项目不改用。在取得可再分发的用户态后端或 FUSE-T 授权之前，**不把本应用当作可商用产品对外销售**。

## 3. 特权模型

优先用 macOS 13+ 的 `SMAppService.daemon` 注册 `Contents/Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist`（**已公证且 Developer ID 签名**时才稳定）。**ad-hoc / 未公证包上 `SMAppService` 通常失败**，回退为管理员密码安装同一 LaunchDaemon。守护进程经 Unix socket 调用应用包内的 `ntfs-rw-helper`，并用调用方 **CDHash + bundle id + 可执行路径** 钉扎。

**不会**写入 `/etc/sudoers.d`。安装/更新/卸载都会删除旧版 `/etc/sudoers.d/ntfs-rw` 和 `/usr/local/sbin/ntfs-rw-helper`。仓库里已删除会写 NOPASSWD 的 `scripts/repair-and-mount.sh`。

持续提权走 `SMAppService` + LaunchDaemon（Cocoa 原生平权）。`osascript` 的 `do shell script … with administrator privileges` **只用于一次性安装/卸载**（ad-hoc 回退）。助手装好后，挂载、卸载、格式化只经 Unix socket，不再弹管理员密码。不引入 `AuthorizationServices` 平行 API。

`helper/ntfs-rw-helper` 是本仓库维护的 **bash 源码**（不是第三方预编译二进制）。`scripts/build.sh` 计算 SHA-256 写入 `Contents/Resources/ntfs-rw-helper.sha256`，并对脚本与 `ntfsmount-helperd` 做 codesign。运行时用该哈希对照 `helper.stamp` / UserDefaults，不匹配则拒绝执行并提示更新助手。

## 4. GitHub Release 的 SHA256

`./scripts/package-dmg.sh` 在 DMG 定稿（含 staple）后会写出：

- `dist/NTFSMount.dmg.sha256`（`HASH  NTFSMount.dmg`）
- `dist/NTFSMount.dmg.release-notes.md`（可贴进 Release 正文）

创建 GitHub Release 时附上 DMG 与 sidecar，并把片段贴进正文。用户校验：

```bash
shasum -a 256 NTFSMount.dmg
```

CI 在 `release: published` 时若 Release 已有 `NTFSMount.dmg` 但没有 sidecar，会补传 `.sha256` 并把哈希写入正文。打 `v*` tag 的 job 会自己附上 DMG 与 sidecar。
