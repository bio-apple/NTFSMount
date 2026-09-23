# 发布检查表 · Release checklist

对外分发前逐项勾选。未公证、未取得 FUSE-T 分发许可时只宜个人使用或 GitHub pre-release。

## 构建

- [ ] `bash scripts/test-helper.sh`
- [ ] `bash scripts/build.sh`
- [ ] `CODESIGN_IDENTITY='Developer ID Application: …' NOTARY_PROFILE=… ./scripts/notarize.sh`
- [ ] `FUSE_T_REDISTRIBUTION_OK=1 ./scripts/package-dmg.sh`（有 FUSE-T 书面授权时才设此变量；否则 DMG 带个人使用说明）
- [ ] 对 DMG 再 `xcrun stapler staple dist/NTFSMount.dmg`（staple 后再算 SHA256；`package-dmg.sh` 已在 staple 之后写出 sidecar）
- [ ] `dist/NTFSMount.dmg.sha256` 已生成（`HASH  NTFSMount.dmg`）

## 安全与范围

- [ ] 外置 NTFS 插入后自动可写（须已同意首次可写确认）
- [ ] 内置 / Boot Camp NTFS **不会**自动挂载；手动挂载有确认框
- [ ] 脏盘 / 休眠只读，且有通知
- [ ] 格式化显示容量/设备号/序列号，必须输入当前卷名，再确认一次；回车默认「取消」；输错拒绝；内置盘拒绝
- [ ] `disk5s1;whoami` 一类 id 被拒绝（selftest）
- [ ] 旧助手已装 → 点「更新挂载助手」→ 黄条消失、可写挂载成功
- [ ] 退出 App 后插入外置 NTFS：LaunchDaemon 仍挂载

## Gatekeeper

- [ ] 干净用户访达双击 DMG → 应用可打开（已公证）
- [ ] 未公证包会提示无法验证开发者；Control-点击「打开」能进，或「系统设置 → 隐私与安全性」点「仍要打开」能进
- [ ] 首次启动只有一个确认框（条款 + 未公证 + 助手提示）；回车是「退出」

## 助手

- [ ] 第一次从窗口横幅或「设置」安装助手（优先系统服务授权，失败才管理员密码）
- [ ] 安装后 **没有** `/etc/sudoers.d/ntfs-rw`，也没有 `/usr/local/sbin/ntfs-rw-helper`
- [ ] 仓库 `helper/*.sh` 与 `scripts/*.sh` 不含 `NOPASSWD:`
- [ ] `ls /var/run/com.bioapple.ntfsmount.sock` 存在
- [ ] 升级后提示更新助手，更新前拒绝用旧助手跑 format
- [ ] 应用内「卸载挂载助手」能去掉守护进程、socket 与 LaunchDaemon

## 界面

- [ ] 菜单栏只有磁盘操作、打开窗口/设置、退出
- [ ] 自动挂载 / 登录 / 程序坞 / 助手 / 日志在窗口「设置」
- [ ] 首次启动只有一个确认框；回车是「退出」
- [ ] 未公证安装助手走管理员密码；已公证优先系统服务
- [ ] 系统 NTFS 只读显示「只读 · 系统 NTFS」；脏盘/休眠显示「只读 · 休眠/未正常关机」
- [ ] `bash scripts/check-helper-gone.sh` 在卸载助手后全部 gone
- [ ] 真盘步骤见 [docs/MANUAL_TEST.md](./MANUAL_TEST.md)

## 日志与许可

- [ ] `~/Library/Logs/ntfsmount.log` 有记录
- [ ] DMG 内有 LICENSE、NOTICE、THIRD_PARTY_LICENSES.md、DISTRIBUTION.md、源码.txt
- [ ] 无 FUSE-T 授权时有「个人使用说明.txt」
- [ ] GitHub Release 在未公证或未授权时标为 pre-release（不要用作 Latest）
- [ ] 禁止第三方镜像；正式下载页须公证 + FUSE-T 书面授权
- [ ] GitHub Release 附上 `NTFSMount.dmg` 与 `NTFSMount.dmg.sha256`，正文列出 SHA256（可粘贴 `dist/NTFSMount.dmg.release-notes.md`）
- [ ] README / DMG 使用说明 / Release 说明写明：仅 Apple Silicon + macOS 13.0+，不支持 Intel Mac（x86_64）
