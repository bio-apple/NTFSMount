# 手工测试 · Manual test

自动化（`./scripts/test-helper.sh`）不插真盘、不装特权助手。对外发布前按本表在 **Apple Silicon + macOS 13+** 上勾选。Intel Mac 不应安装。

日志：`~/Library/Logs/ntfsmount.log`

## 安装与 Gatekeeper

- [ ] 未公证 DMG：双击被拦截 → Control-click 打开，或「系统设置 → 隐私与安全性 → 仍要打开」
- [ ] 首次启动只有**一个**确认框（条款 + 未公证说明 + 助手安装提示）；回车是「退出」，点「同意并继续」才进入
- [ ] 同意后出现主窗口，横幅「安装…」；兼容性说明在左侧「设置」，不再弹第二窗
- [ ] 未公证：安装助手走管理员密码；安装后没有 `/etc/sudoers.d/ntfs-rw`
- [ ] 已公证（若有）：优先系统服务授权，失败才要密码

## 真盘

准备：一块外置 NTFS；可选一块 Windows 休眠/快速启动未关的盘；不要用 Boot Camp 当自动挂载对象。

- [ ] 插入外置 NTFS → 自动可写（须已同意首次可写确认）
- [ ] 菜单栏状态为「可写」；访达可拷贝文件
- [ ] 「推出（可安全拔出）」→ 访达消失后再拔线
- [ ] 系统 NTFS 只读挂载：状态为「只读 · 系统 NTFS」，子菜单「以可写方式挂载」成功后变可写
- [ ] 脏盘 / 休眠：状态为「只读 · 休眠/未正常关机」，只读挂载并通知；不要静默清 hiberfile
- [ ] 内置 / Boot Camp：**不会**自动挂载；手动可写有确认框

## 格式化（外置整盘，会抹盘）

- [ ] 对话框显示容量、设备号、序列号/UUID；回车是「取消」
- [ ] 输错卷名拒绝；输对后还有一次「最后确认」
- [ ] 内置盘菜单里格式化不可用

## 卸载（助手）

窗口 **设置 → 卸载助手** 后执行 `bash scripts/check-helper-gone.sh`，下列路径必须不存在：

- `/var/run/com.bioapple.ntfsmount.sock`
- `/Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist`
- `/Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist`
- `/Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd`
- `/Library/Application Support/NTFSMount`
- `/etc/sudoers.d/ntfs-rw`
- `/usr/local/sbin/ntfs-rw-helper`

完全删除应用再用 `./uninstall.sh`，并确认 `/Applications/NTFSMount.app` 已去掉。系统里若另装过 FUSE-T 不会被删。

## 升级

- [ ] 旧版 sudoers 机器打开新包 → 「更新挂载助手」→ 更新后 `check-helper-gone.sh` 里 sudoers 项消失，可写挂载成功
