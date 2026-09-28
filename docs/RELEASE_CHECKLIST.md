# 发布检查表 · Release checklist

对外分发前勾选。未公证、未取得 FUSE-T 分发许可时只宜个人使用或 GitHub **pre-release**（不要当 Latest）。

## 构建

- [ ] `bash scripts/test-helper.sh`
- [ ] `bash scripts/build.sh`（`.app` 内含 LICENSE、**NOTICE**、THIRD_PARTY_LICENSES.md、DISTRIBUTION.md）
- [ ] 本机公证：`CODESIGN_IDENTITY='Developer ID Application: …' NOTARY_PROFILE=… ./scripts/notarize.sh`；或配齐 CI Secrets
- [ ] 推送 `v*` tag 后 Actions「DMG (tag)」成功，Release 含 `NTFSMount.dmg` 与 `.sha256`
- [ ] 无 FUSE-T 书面授权时 **不要** 设 `FUSE_T_REDISTRIBUTION_OK=1`
- [ ] `dist/NTFSMount.dmg.sha256` 在 staple 之后生成

## 安全与范围

- [ ] 外置 NTFS：菜单「以可写方式挂载」；自动挂载不是卖点
- [ ] 内置 / Boot Camp **不会**自动挂载；手动可写有确认框
- [ ] 脏盘 / 休眠只读；不静默清 hiberfile；ntfsfix 回车默认取消
- [ ] 「全部以可写方式挂载」逐盘走与单盘相同的健康探测对话框
- [ ] 格式化：根菜单「抹掉整盘为 NTFS…」（卷子菜单里没有）；容量/设备号/序列号；输入当前名；两步；**回车=取消**
- [ ] 可能加密 / BitLocker 线索盘：空状态提示；格式化框有警告
- [ ] `disk5s1;whoami` 一类 id 被拒绝（selftest）
- [ ] 旧助手 →「更新挂载助手」；`HELPER_VERSION=9`
- [ ] 安装后 **没有** `/etc/sudoers.d/ntfs-rw`

## Gatekeeper 与界面

- [ ] 未公证：Control-click 打开，或「仍要打开」
- [ ] 首次确认框：回车同意，Esc 退出
- [ ] 关主窗口后菜单栏 **NTFS** 仍在；悬停图标有四行卡片
- [ ] 空闲图标无问号 badge；诊断为可滚动窗口（不是一份 Alert）
- [ ] 设置首页无 Issue 号 / CDHash / appcast 长文
- [ ] 仅 Apple Silicon + macOS 13.0+ 文案出现在 README / DMG / Release

## Sparkle 与 Release

- [ ] `appcast.xml` 覆盖上传到 **v1.2.0** 资产 URL（`SUFeedURL` 钉死此处），**不是** Latest
- [ ] `SUEnableAutomaticChecks` 默认 false；私钥未进仓库
- [ ] GitHub Release 在未公证或未授权时标为 pre-release
- [ ] 禁止第三方镜像

真盘步骤：[docs/MANUAL_TEST.md](./MANUAL_TEST.md)。分发：[docs/DISTRIBUTION.md](./DISTRIBUTION.md)。
