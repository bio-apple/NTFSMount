# 分发状态 · Distribution status

直发应用，不上 Mac App Store。仅支持 Apple Silicon（M 芯片）与 macOS 13.0+，**不支持 Intel Mac（x86_64）**；构建为 arm64，不要做 Intel / 通用二进制。下面两项在打正式对外包之前必须完成；未完成时只宜个人使用或标成预发布。

## 1. Apple 公证 · Notarization

需要付费 Apple Developer Program 的 **Developer ID Application** 证书，以及 `notarytool` 钥匙串配置。

```bash
CODESIGN_IDENTITY='Developer ID Application: Name (TEAM)' \
NOTARY_PROFILE='notarytool-profile' \
./scripts/package-dmg.sh
```

`scripts/notarize.sh` 会对应用与内嵌二进制做 Hardened Runtime 签名、提交公证并 staple。未设置证书时构建为 ad-hoc：Gatekeeper 会拦截，需按住 Control 点应用 → 打开；也可在「系统设置 → 隐私与安全性」点「仍要打开」。

CI：若仓库 Secrets 含 `CODESIGN_IDENTITY` / `NOTARY_PROFILE`，会尝试公证。打 `v*` tag 且 `runtime/` 齐全时自动生成预发布 DMG；GitHub Latest 不会指向预发布。

## 2. FUSE-T `go-nfsv4`

捆绑的 `go-nfsv4` **不是 GPL**。FUSE-T 写明个人使用免费；作为产品嵌入或分发可能需要商业许可。

- 联系：https://www.fuse-t.org/
- 取得书面授权后：`FUSE_T_REDISTRIBUTION_OK=1 ./scripts/package-dmg.sh`，并把本文件此节改为「已授权」。
- 未设置该变量时，DMG 带「个人使用说明」，GitHub Release **必须**标为 pre-release；**不要**把该包当作 GitHub Latest，也禁止第三方镜像。
- 正式对外下载页必须同时完成 Developer ID 公证与 FUSE-T 书面授权。许可证拆分见仓库根目录 [NOTICE](../NOTICE)。

macFUSE 依赖内核扩展，本项目不改用。在取得可再分发的用户态后端或 FUSE-T 授权之前，**不把本应用当作可商用产品对外销售**。

## 3. 特权模型

优先用 macOS 13+ 的 `SMAppService.daemon` 注册 `Contents/Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist`（**已公证且 Developer ID 签名**时才稳定）。**ad-hoc / 未公证包上 `SMAppService` 通常失败**，回退为管理员密码安装同一 LaunchDaemon。守护进程经 Unix socket 调用应用包内的 `ntfs-rw-helper`，并用调用方 **CDHash + bundle id + 可执行路径** 钉扎。

**不会**写入 `/etc/sudoers.d`。安装/更新/卸载都会删除旧版 `/etc/sudoers.d/ntfs-rw` 和 `/usr/local/sbin/ntfs-rw-helper`。仓库里已删除会写 NOPASSWD 的 `scripts/repair-and-mount.sh`。

`helper/ntfs-rw-helper` 是本仓库维护的 **bash 源码**（不是第三方预编译二进制）。`scripts/build.sh` 计算 SHA-256 写入 `Contents/Resources/ntfs-rw-helper.sha256`，并对脚本与 `ntfsmount-helperd` 做 codesign。运行时用该哈希对照 `helper.stamp` / UserDefaults，不匹配则拒绝执行并提示更新助手。

## 4. GitHub Release 的 SHA256

`./scripts/package-dmg.sh` 在 DMG 定稿（含 staple）后会写出：

- `dist/NTFSMount.dmg.sha256`（`HASH  NTFSMount.dmg`）
- `dist/NTFSMount.dmg.release-notes.md`（可贴进 Release 正文）

创建 GitHub Release 时附上 DMG 与 sidecar，并把片段贴进正文。用户校验：

```bash
shasum -a 256 NTFSMount.dmg
```

CI 在 `release: published` 时若 Release 已有 `NTFSMount.dmg`，会补传 `.sha256` 并把哈希写入正文；workflow 本身不创建 Release。
