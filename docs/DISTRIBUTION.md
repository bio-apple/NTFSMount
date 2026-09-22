# 分发状态 · Distribution status

直发应用，不上 Mac App Store。下面两项在打正式对外包之前必须完成；未完成时只宜个人使用或标成预发布。

## 1. Apple 公证 · Notarization

需要付费 Apple Developer Program 的 **Developer ID Application** 证书，以及 `notarytool` 钥匙串配置。

```bash
CODESIGN_IDENTITY='Developer ID Application: Name (TEAM)' \
NOTARY_PROFILE='notarytool-profile' \
./scripts/package-dmg.sh
```

`scripts/notarize.sh` 会对应用与内嵌二进制做 Hardened Runtime 签名、提交公证并 staple。未设置证书时构建为 ad-hoc：Gatekeeper 会拦截，需按住 Control 点应用 → 打开。

CI：若仓库 Secrets 含 `MACOS_CERTIFICATE` / `NOTARY_PROFILE`，tag 构建会公证；否则只编译。

## 2. FUSE-T `go-nfsv4`

捆绑的 `go-nfsv4` **不是 GPL**。FUSE-T 写明个人使用免费；作为产品嵌入或分发可能需要商业许可。

- 联系：https://www.fuse-t.org/
- 取得书面授权后：`FUSE_T_REDISTRIBUTION_OK=1 ./scripts/package-dmg.sh`，并把本文件此节改为「已授权」。
- 未设置该变量时，DMG 带「个人使用说明」，GitHub Release 标为 pre-release。

macFUSE 依赖内核扩展，本项目不改用。在取得可再分发的用户态后端或 FUSE-T 授权之前，**不把本应用当作可商用产品对外销售**。

## 3. 特权模型

挂载助手是系统 LaunchDaemon（`com.bioapple.ntfsmount.helper`），经 Unix socket 调密封在应用包内的 `ntfs-rw-helper`。守护进程用调用方 **CDHash + bundle id + 可执行路径** 钉扎，不再使用 `/etc/sudoers.d` 免密。旧版 sudoers 会在更新助手时删除。

macOS 13+ 也会尝试 `SMAppService.daemon` 注册同一 plist（`Contents/Library/LaunchDaemons`）；失败则回退到管理员密码安装 LaunchDaemon。
