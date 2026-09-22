# 发布检查表 · Release checklist

对外分发前逐项勾选。未公证不要发给非技术用户。

## 构建

- [ ] `bash scripts/test-helper.sh`
- [ ] `bash scripts/build.sh`
- [ ] `CODESIGN_IDENTITY='Developer ID Application: …' NOTARY_PROFILE=… ./scripts/notarize.sh`
- [ ] `./scripts/package-dmg.sh`（公证后再打包，或对 DMG 再 staple）

## 安全与范围

- [ ] 外置 NTFS 插入后自动可写
- [ ] 内置 / Boot Camp NTFS **不会**自动挂载；手动挂载有确认框
- [ ] 脏盘 / 休眠只读，且有通知
- [ ] 格式化必须输入当前卷名；内置盘拒绝
- [ ] `disk5s1;whoami` 一类 id 被拒绝（selftest）

## Gatekeeper

- [ ] 干净用户访达双击 DMG → 应用可打开（已公证）
- [ ] 未公证包会提示无法验证开发者

## 助手

- [ ] 第一次从窗口横幅安装助手
- [ ] 升级后提示更新助手，更新前拒绝用旧助手跑 format
- [ ] 应用内「卸载挂载助手」能去掉 sudoers 与 LaunchDaemon

## 日志与许可

- [ ] `~/Library/Logs/ntfsmount.log` 有记录
- [ ] DMG 内有 LICENSE、THIRD_PARTY_LICENSES.md、源码.txt
