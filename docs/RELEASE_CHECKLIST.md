# 发布检查表 · Release checklist

对外分发前勾选。未公证、未取得 FUSE-T 分发许可时只宜个人使用。README 走 GitHub Latest；不要把该包当成可再分发产品。

## 构建

- [ ] `bash scripts/test-helper.sh`
- [ ] `bash scripts/build.sh`（`.app` 内含 LICENSE、**NOTICE**、THIRD_PARTY_LICENSES.md、DISTRIBUTION.md）
- [ ] 本机公证：`CODESIGN_IDENTITY='Developer ID Application: …' NOTARY_PROFILE=… ./scripts/notarize.sh`；或配齐 CI Secrets
- [ ] 推送 `v*` tag 后 Actions「PKG (tag)」成功，Release 含 `NTFSMount.pkg` 与 `.sha256`
- [ ] 无 FUSE-T 书面授权时 **不要** 设 `FUSE_T_REDISTRIBUTION_OK=1`
- [ ] `dist/NTFSMount.pkg.sha256` 在 staple 之后生成

## 安全与范围

- [ ] 外置 NTFS：菜单「以可写方式挂载」；自动挂载不是卖点
- [ ] 内置 / Boot Camp **不会**自动挂载；手动可写有确认框
- [ ] 脏盘 / 休眠只读；不静默清 hiberfile；ntfsfix 回车默认取消
- [ ] 「全部以可写方式挂载」逐盘走与单盘相同的健康探测对话框
- [ ] 格式化：根菜单「抹掉整盘为 NTFS…」（卷子菜单里没有）；容量/设备号/序列号；输入当前名；两步；**回车=取消**
- [ ] 可能加密 / BitLocker 线索盘：空状态提示；格式化框有警告
- [ ] `disk5s1;whoami` 一类 id 被拒绝（selftest）
- [ ] 旧助手 →「更新挂载助手」；`HELPER_VERSION=10`
- [ ] 安装后 **没有** `/etc/sudoers.d/ntfs-rw`

## Gatekeeper 与界面

- [ ] 未公证：Control-click 打开，或「仍要打开」
- [ ] 首次确认框：回车同意，Esc 退出
- [ ] 关主窗口后菜单栏 **NTFS** 仍在；悬停图标有四行卡片
- [ ] 空闲图标无问号 badge；诊断为可滚动窗口（不是一份 Alert）
- [ ] 设置首页无 Issue 号 / CDHash / appcast 长文
- [ ] 仅 Apple Silicon + macOS 13.0+ 文案出现在 README / 安装包 / Release

## GitHub Release notes

推 `v*` tag 时，`PKG (tag)` 用 `scripts/generate-release-notes.sh` 从上一枚 `v*` tag 的 `git log` 生成正文（What's new / Fixes / Breaking Changes / Changes / Helper reinstall / Old config）。手写 `docs/RELEASE_NOTES/<version>.md` 是可选覆盖；缺文件不再挡发布。CHANGELOG.md 仍手工更新，CI 不会往 `main` 提交。

- [ ] 推 tag 前可预览：`bash scripts/generate-release-notes.sh <version>`
- [ ] 可选：从 [RELEASE_NOTES_TEMPLATE.md](./RELEASE_NOTES_TEMPLATE.md) 复制为 `docs/RELEASE_NOTES/<version>.md` 并填好；含 `_TBD` / `**Yes / No**` 时 CI 忽略该文件、改用生成稿
- [ ] 正文含：**What's new**、**Fixes**、**Known issues**（未公证、个人使用、FUSE-T 非 GPL）、**Breaking Changes**、**Changes**
- [ ] **Helper: reinstall required? yes/no**（生成稿按 HELPER_VERSION / helperd / IPC / CDHash / install-helper 推断；No 时仍写 verify）
- [ ] **Old config compatibility**：UserDefaults、自动挂载、helper stamp、残留 sudoers（生成稿不省略这些小节）
- [ ] 文首保留个人使用、未公证的法律一句；GitHub Release 贴同一份（CI 会再附安装包 SHA256）
- [ ] Optional: update root [CHANGELOG.md](../CHANGELOG.md) (not auto-committed)

## Sparkle 与 Release

- [ ] `appcast.xml` 覆盖上传到 **v1.0** 资产 URL（`SUFeedURL` 钉在此处），**不是** Latest
- [ ] `SUEnableAutomaticChecks` / `SUAutomaticallyUpdate` 默认 false；未公证包不 start Sparkle、无「检查更新…」菜单
- [ ] 私钥未进仓库
- [ ] GitHub Release 标题/正文写明个人使用、未公证；README Latest URL 依赖非 prerelease
- [ ] 禁止第三方镜像

真盘步骤：[docs/MANUAL_TEST.md](./MANUAL_TEST.md)。分发：[docs/DISTRIBUTION.md](./DISTRIBUTION.md)。模板：[RELEASE_NOTES_TEMPLATE.md](./RELEASE_NOTES_TEMPLATE.md)。
