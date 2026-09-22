# 发布检查表 · Release checklist

对外分发前逐项勾选。未公证、未取得 FUSE-T 分发许可时只宜个人使用或 GitHub pre-release。

## 构建

- [ ] `bash scripts/test-helper.sh`
- [ ] `bash scripts/build.sh`
- [ ] `CODESIGN_IDENTITY='Developer ID Application: …' NOTARY_PROFILE=… ./scripts/notarize.sh`
- [ ] `FUSE_T_REDISTRIBUTION_OK=1 ./scripts/package-dmg.sh`（有 FUSE-T 书面授权时才设此变量；否则 DMG 带个人使用说明）
- [ ] 对 DMG 再 `xcrun stapler staple dist/NTFSMount.dmg`

## 安全与范围

- [ ] 外置 NTFS 插入后自动可写（须已同意首次可写确认）
- [ ] 内置 / Boot Camp NTFS **不会**自动挂载；手动挂载有确认框
- [ ] 脏盘 / 休眠只读，且有通知
- [ ] 格式化必须输入当前卷名；输错拒绝；内置盘拒绝
- [ ] `disk5s1;whoami` 一类 id 被拒绝（selftest）
- [ ] 旧助手已装 → 点「更新挂载助手」→ 黄条消失、可写挂载成功
- [ ] 退出 App 后插入外置 NTFS：LaunchDaemon 仍挂载

## Gatekeeper

- [ ] 干净用户访达双击 DMG → 应用可打开（已公证）
- [ ] 未公证包会提示无法验证开发者；Control-点击「打开」能进
- [ ] 首次启动有未公证提示（ad-hoc）和个人使用 / 备份确认

## 助手

- [ ] 第一次从窗口横幅或「设置」安装助手（管理员密码一次）
- [ ] 安装后 **没有** `/etc/sudoers.d/ntfs-rw`
- [ ] `ls /var/run/com.bioapple.ntfsmount.sock` 存在
- [ ] 升级后提示更新助手，更新前拒绝用旧助手跑 format
- [ ] 应用内「卸载挂载助手」能去掉守护进程、socket 与 LaunchDaemon

## 界面

- [ ] 菜单栏只有磁盘操作、打开窗口/设置、退出
- [ ] 自动挂载 / 登录 / 程序坞 / 助手 / 日志在窗口「设置」
- [ ] 失败信息不是 osascript 原文
- [ ] 设置页能看到 `~/Library/Logs/ntfsmount.log` 尾部

## 日志与许可

- [ ] `~/Library/Logs/ntfsmount.log` 有记录
- [ ] DMG 内有 LICENSE、THIRD_PARTY_LICENSES.md、DISTRIBUTION.md、源码.txt
- [ ] 无 FUSE-T 授权时有「个人使用说明.txt」
- [ ] GitHub Release 在未公证或未授权时标为 pre-release
