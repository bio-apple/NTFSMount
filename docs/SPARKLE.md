# Sparkle 自动更新

本应用用 [Sparkle](https://sparkle-project.org/) 检查 GitHub Releases 上的 DMG。当前包是 **ad-hoc / 未公证** 的个人使用预发布；**不要**把更新描述成已公证或 Developer ID 可信。

## 用户侧

- 菜单 **检查更新…**：随时可用，一点就会访问 feed。
- 设置 **自动检查更新**：默认 **关闭**。打开前应用不会为更新去联网。
- 打开自动检查后：定期向 GitHub 拉 Sparkle `appcast.xml`（HTTPS）。不会静默安装；发现新版本后可在 Sparkle 对话框里一键安装。
- 更新档案用 **Sparkle EdDSA** 验签。Apple 代码签名目前是 ad-hoc，**不能**用 Developer ID / 公证来证明更新来源。

Feed（不是 GitHub Latest）：

`https://github.com/bio-apple/NTFSMount/releases/download/v1.2.0/appcast.xml`

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

1. `./scripts/package-dmg.sh` 得到 `dist/NTFSMount.dmg`
2. `./scripts/sparkle-generate-appcast.sh`（可选 `SPARKLE_RELEASE_TAG=v1.2.0`）
3. 把 `dist/appcast.xml` 上传到 **同一个** GitHub Release（默认 `v1.2.0`，且该 Release 必须是 pre-release，**不要**标成 Latest）：

```bash
gh release upload v1.2.0 --clobber dist/appcast.xml
```

`generate_appcast` 会给 DMG 写 `sparkle:edSignature`。enclosure URL 形如：

`https://github.com/bio-apple/NTFSMount/releases/download/v1.2.0/NTFSMount.dmg`

已装 1.2.0 的应用会一直读这个 feed URL。发 1.3.0 时：把新 DMG 传到 `v1.3.0`，再生成一份**列出新版本**的 `appcast.xml`，用 `--clobber` **覆盖 v1.2.0 上的 appcast.xml**。不要改用 `/releases/latest/download/appcast.xml`，除非 FUSE-T 再分发与公证都已完成。

需要 Sparkle CLI 时，脚本会从 GitHub 拉取钉死的 Sparkle 2.10.0 工具包（或使用 `SPARKLE_BIN` / SPM artifacts 里的 `generate_appcast`）。

## 构建嵌入

`scripts/build.sh` 把 `Sparkle.framework` 放进 `NTFSMount.app/Contents/Frameworks` 并签名。ad-hoc 包使用 `Resources/NTFSMount-adhoc.entitlements`（关闭 library validation），否则 Hardened Runtime 会拒绝加载未带 Team ID 的 Sparkle。Developer ID 构建仍用 `NTFSMount.entitlements`，并把 Sparkle 签成同一身份。

`Info.plist`：`SUEnableAutomaticChecks=false`，`SUAutomaticallyUpdate=false`。
