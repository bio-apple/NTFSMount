# 分发状态 · Distribution status

> **Do not ship or sell until you have a written FUSE-T license and Developer ID notarization.**

本文不是法律意见。混合许可下的二进制分发是否合规 **需律师确认**。条款摘要见 [NOTICE](../NOTICE) 与 [THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md)；不要把本文件当成对 FUSE-T 或 GPL 的授权解释。

**当前公开渠道为 GitHub Release（个人使用，未公证）。在取得 FUSE-T 书面许可并公证之前，这不是可再分发的产品。**

直发应用，不上 Mac App Store。仅支持 Apple Silicon（M 芯片）与 macOS 13.0+，**不支持 Intel Mac（x86_64）**；构建为 arm64，不要做 Intel / 通用二进制。下面两项在打正式对外包之前必须完成；未完成时只宜个人使用或标成预发布。

## Component licenses · 组件许可

| Component | License (as documented in-repo) |
| --- | --- |
| NTFSMount Swift / helper scripts | GPL-2.0-or-later ([LICENSE](../LICENSE)) |
| Bundled ntfs-3g / mkntfs / ntfsfix / libntfs-3g | GPL-2.0 |
| `libfuse.2.dylib` | LGPL-2.1 |
| Sparkle.framework | MIT |
| FUSE-T `go-nfsv4` | **Not GPL.** NOTICE: personal / non-commercial use by default; commercial use or bundling with commercial software requires a commercial license from the FUSE-T authors ([fuse-t.org](https://www.fuse-t.org/)). |

NOTICE quotes FUSE-T: *“Free for non-commercial use”* and *“For commercial use or/and bundling with commercial software the software vendor has to obtain a commercial license from the FUSE-T authors.”* `go-nfsv4` is excluded from the repo’s GPL grant.

Shipping a prebuilt `.app` / DMG that mixes GPL ntfs-3g, LGPL libfuse, MIT Sparkle, and non-GPL `go-nfsv4` is **not confirmed compliant**. **需律师确认.**

## Self-compile vs prebuilt DMG · 自行编译与预编译 DMG

Compiling from this Git tree and downloading a GitHub DMG are different distribution acts. The repo LICENSE covers this project’s Swift/helper sources (GPL-2.0-or-later) and does **not** make the bundled `go-nfsv4` binary GPL. A prebuilt DMG that already contains `go-nfsv4` is a binary redistribution of FUSE-T’s NFS server; GitHub Releases marked pre-release are **not** a commercial distribution grant (NOTICE). Do not tell users the DMG is “the same license as the repo.” **需律师确认.**

## Commercialization · 商业化

Before shipping or selling as a product: written FUSE-T commercial / bundling license; Developer ID Application signing **and** notarization; do not sell, third-party-mirror, or put this on the Mac App Store while those are missing. GPL obligations for ntfs-3g (corresponding source, notices) still apply if you distribute those binaries. Set `FUSE_T_REDISTRIBUTION_OK=1` only after written FUSE-T permission **and** notarization. **需律师确认.**

Contact: [fuse-t.org](https://www.fuse-t.org/)

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

`.github/workflows/build.yml`：push 到 `main` 与 PR 会跑 SwiftLint / ShellCheck / shfmt / Markdown lint / UnitTest / Security Scan / Build（`swift build`，不 `brew install ntfs-3g`）；`main` 上另打 `.app` 工件。推送 `v*` tag 时打 DMG，在日志打印 `SHA256=`，并把 `NTFSMount.dmg` + `NTFSMount.dmg.sha256` 作为 Artifact 上传，再创建 GitHub Release。随后 **Release SHA256** 对已发布 DMG 再算一遍哈希。**不要在真盘 workflow 里公证**；`.github/workflows/manual-disk-test.yml` 不读这些 secrets。

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
| `FUSE_T_REDISTRIBUTION_OK` | **仓库变量**（`vars.`，不是 secret）。仅在已公证 **且** 已有 FUSE-T 书面许可时设为 `1`，才可当产品再分发 |

本机仍可用 `NOTARY_PROFILE`。证书与 API Key 齐了才会 `notarytool submit`；缺一则仍是未公证个人使用包。未取得 FUSE-T 书面许可不要设 `FUSE_T_REDISTRIBUTION_OK`。GitHub Latest 可以指向这份个人使用 DMG；当作产品再分发仍须公证 **并且** FUSE-T 许可证允许。

```bash
git tag v0.1.0
git push origin v0.1.0
```

## 2. FUSE-T `go-nfsv4`

捆绑的 `go-nfsv4` **不是 GPL**。FUSE-T 写明个人使用免费；作为产品嵌入或分发可能需要商业许可。钉死 **FUSE-T 1.2.7**（`scripts/prepare-runtime.sh` 的 `FUSE_T_VERSION` 与 [runtime/versions.txt](../runtime/versions.txt)）；Package.swift 无法钉 macOS pkg。

- 联系：[fuse-t.org](https://www.fuse-t.org/)
- 取得书面授权后：`FUSE_T_REDISTRIBUTION_OK=1 ./scripts/package-dmg.sh`，并把本文件此节改为「已授权」。
- 未设置该变量时，DMG 带 `Personal Use.txt`。GitHub Latest 可以指向这份个人使用包（README 的 `/releases/latest/download/NTFSMount.dmg`），**不要**把它当成可再分发或可销售的产品，也禁止第三方镜像。
- **当作产品对外再分发**仅当已公证并且 FUSE-T 许可证允许再分发（仓库变量 `vars.FUSE_T_REDISTRIBUTION_OK=1`）。缺一不可。
- 正式对外下载页必须同时完成 Developer ID 公证与 FUSE-T 书面授权。许可证拆分见仓库根目录 [NOTICE](../NOTICE)。

macFUSE / osxfuse 依赖内核扩展，与 **SIP 保持开启** 不兼容。本项目用 FUSE-T（用户态 NFS/WebDAV），不改用 kext。开发机检查：`./scripts/check-fuse-deps.sh`（不要 `brew install macfuse`）。在取得可再分发的用户态后端或 FUSE-T 授权之前，**不把本应用当作可商用产品对外销售**。

## 3. 特权模型

优先用 macOS 13+ 的 `SMAppService.daemon` 注册 `Contents/Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist`（**已公证且 Developer ID 签名**时才稳定）。**ad-hoc / 未公证包上 `SMAppService` 通常失败**，回退为管理员密码安装同一 LaunchDaemon。守护进程经 Unix socket 只执行 `/Library/Application Support/NTFSMount/ntfs-rw-helper`（root:wheel 755 副本），并用 `SecCodeCheckValidity` / `SecStaticCodeCheckValidity` 加上**安装时写入的** `allowed.cdhash` 钉扎调用方，不只对照现场 `.app` 的 CDHash。

**不会**写入 `/etc/sudoers.d`。安装/更新/卸载都会删除旧版 `/etc/sudoers.d/ntfs-rw` 和 `/usr/local/sbin/ntfs-rw-helper`。仓库里已删除会写 NOPASSWD 的 `scripts/repair-and-mount.sh`。

持续提权走 `SMAppService` + LaunchDaemon（Cocoa 原生平权）。**ad-hoc / 未公证包上 `SMAppService` 通常失败**，一次性安装/卸载回退为 Security.framework **Authorization Services**（`AuthorizationCreate` / `AuthorizationCopyRights` 申请 `kAuthorizationRightExecute`，再以特权运行捆绑的 `install-helper.sh` / `uninstall-helper.sh`）。不嵌入 `sudo`，也不使用 `osascript` 的 `do shell script … with administrator privileges`。`AuthorizationExecuteWithPrivileges` 已弃用，仅作为 ad-hoc 回退经 `dlsym` 解析；已公证 Developer ID 包优先 `SMAppService`，不依赖公证才能个人使用。助手装好后，挂载、卸载、格式化只经 Unix socket，不再弹管理员对话框。不写 sudoers，**SIP 保持开启，不装 kext**。

`helper/ntfs-rw-helper` 是本仓库维护的 **bash 源码**（不是第三方预编译二进制，`HELPER_VERSION=10`）。`scripts/build.sh` 计算 SHA-256 写入 `Contents/Resources/ntfs-rw-helper.sha256`，并对脚本与 `ntfsmount-helperd` 做 codesign。运行时用该哈希对照 `helper.stamp` / UserDefaults，不匹配则拒绝执行并提示更新助手。`.app` 内同时放入 `LICENSE`、`NOTICE`、`THIRD_PARTY_LICENSES.md`、`DISTRIBUTION.md`。

IPC：**v2** 长度前缀（单参最长 1024、最多 32 个参数），旧守护进程回「协议错误」时回退 v1。format / fix / ntfsfix 等待 **600 秒**并发送 NUL 心跳；其它命令 180 秒。本进程对 daemon 的调用串行化。读完 argv 后若客户端已断开则 **不 exec**。

出口管制口径：捆绑的 Sparkle 走系统 TLS 与 EdDSA 验签，不提供非豁免加密。未公证构建不启动 Sparkle、不在应用内检查更新。`ITSAppUsesNonExemptEncryption=false`。若以后对卷内容做加密类功能，必须重评该键。

## 4. GitHub Release 的 SHA256

`./scripts/package-dmg.sh` 在 DMG 定稿（含 staple）后会写出：

- `dist/NTFSMount.dmg.sha256`（`HASH  NTFSMount.dmg`）
- `dist/NTFSMount.dmg.release-notes.md`（可贴进 Release 正文）

创建 GitHub Release 时附上 DMG 与 sidecar，并把 SHA256 片段贴进正文。推 `v*` tag 时 CI 用 `scripts/generate-release-notes.sh` 从 git log 生成 What’s new / Fixes / Breaking / Helper reinstall / Old config（手写 [RELEASE_NOTES_TEMPLATE.md](./RELEASE_NOTES_TEMPLATE.md) 为可选覆盖）。用户校验：

```bash
shasum -a 256 NTFSMount.dmg
```

CI 在 `release: published` 时若 Release 已有 `NTFSMount.dmg` 但没有 sidecar，会补传 `.sha256` 并把哈希写入正文。打 `v*` tag 的 job 会自己附上 DMG 与 sidecar。

## 5. Sparkle 更新

未公证个人使用构建：**不要**把应用内更新当产品功能。用户到 GitHub Releases 手动下载 DMG。菜单不展示「检查更新…」；设置无自动检查开关。`SUEnableAutomaticChecks` / `SUAutomaticallyUpdate` 为 false；进程不 start Sparkle。

维护者：自动更新用 Sparkle EdDSA 签 DMG / appcast，**不是**用 GitHub Releases Atom，也**不要**把 feed 指到 GitHub Latest（FUSE-T 仍为个人使用预发布时）。

`SUFeedURL` 仍钉在 **v1.2.0 资产 URL**。发 1.2.1 及以后版本时：把新 DMG 传到对应 tag，再生成 appcast，用 `--clobber` **覆盖 v1.2.0 上的 `appcast.xml`**。

- Feed：`https://github.com/bio-apple/NTFSMount/releases/download/v1.2.0/appcast.xml`
- 密钥与 `generate_appcast` 步骤：[docs/SPARKLE.md](./SPARKLE.md)
