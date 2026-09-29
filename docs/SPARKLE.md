# Sparkle 自动更新

本仓库仍嵌入 [Sparkle](https://sparkle-project.org/)，供**以后已公证构建**使用。当前包是 **ad-hoc / 未公证** 的个人使用预发布：**不要**把应用内更新描述成产品功能，也**不要**描述成已公证或 Developer ID 可信。

## 用户侧

未公证构建：

- 菜单**没有**「检查更新…」。
- 设置**没有**自动检查开关或「检查更新」按钮；写死为到 [GitHub Releases](https://github.com/bio-apple/NTFSMount/releases) 手动下载安装包。
- 进程启动时**不** start Sparkle；`checkForUpdates()` 为空操作，不会访问网络。

`Info.plist`：`SUEnableAutomaticChecks=false`，`SUAutomaticallyUpdate=false`。`SUFeedURL` 仍保留给公证后启用。

## 维护者：feed 钉死

Feed（不是 GitHub Latest）：

`https://github.com/bio-apple/NTFSMount/releases/download/v1.0/appcast.xml`

GitHub Releases 的 Atom 不能当 Sparkle feed 用。

## 密钥（只做一次）

私钥**禁止进 Git**。

```bash
./scripts/sparkle-generate-keys.sh
```

- 公钥：脚本打印 `SUPublicEDKey=…`，写入 `Resources/Info.plist`。
- 私钥：默认 `~/Library/Application Support/NTFSMount-sparkle/eddsa-private.key`（32 字节 Ed25519 seed 的 base64）。可用环境变量 `NTFSMOUNT_SPARKLE_KEYDIR` 改目录。
- 已有密钥时脚本不会轮换，只打印公钥和私钥**路径**（不打印私钥内容）。

丢失私钥后，ad-hoc 构建无法按 Sparkle 的 Developer ID 密钥轮换规则补救；只能换公钥并让用户重装。

## 生成并发布 appcast

1. `./scripts/package-pkg.sh` 得到 `dist/NTFSMount.pkg`
2. `./scripts/sparkle-generate-appcast.sh`（可选 `SPARKLE_RELEASE_TAG=v1.0`）
3. 把 `dist/appcast.xml` 上传到 **v1.0** Release。未公证时 **不要** 把 feed 改成 Latest：

```bash
gh release upload v1.0 --clobber dist/appcast.xml
```

`generate_appcast` 会给安装包写 `sparkle:edSignature`。enclosure URL 形如：

`https://github.com/bio-apple/NTFSMount/releases/download/v1.0/NTFSMount.pkg`

当前应用读的就是这个 feed URL。以后发新版本时，把新安装包传到对应 tag，再生成 appcast。不要改用 `/releases/latest/download/appcast.xml`，除非 FUSE-T 再分发与公证都已完成。

需要 Sparkle CLI 时，脚本会从 GitHub 拉取钉死的 Sparkle 2.10.0 工具包（或使用 `SPARKLE_BIN` / SPM artifacts 里的 `generate_appcast`）。

## 构建嵌入

`scripts/build.sh` 把 `Sparkle.framework` 放进 `NTFSMount.app/Contents/Frameworks` 并签名。ad-hoc 包使用 `Resources/NTFSMount-adhoc.entitlements`（关闭 library validation），否则 Hardened Runtime 会拒绝加载未带 Team ID 的 Sparkle。Developer ID 构建仍用 `NTFSMount.entitlements`，并把 Sparkle 签成同一身份。

`Info.plist`：`SUEnableAutomaticChecks=false`，`SUAutomaticallyUpdate=false`。
