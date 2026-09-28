# 手工测试 · Manual test

自动化（`./scripts/test-helper.sh`）不插真盘、不装特权助手。对外发布前按本表在 **Apple Silicon + macOS 13+** 上勾选。Intel Mac 不应安装。

可选 CI：手动触发 [`.github/workflows/manual-disk-test.yml`](../.github/workflows/manual-disk-test.yml)（`workflow_dispatch`，`runs-on: [self-hosted, macOS, ARM64]`）。无 NTFS 盘会立刻失败，不空等。GitHub-hosted runner 插不了 USB。可脚本化步骤见 `scripts/ci-manual-disk-test.sh`；Gatekeeper / 访达 / 格式化仍须人工勾选。

日志：`~/Library/Logs/ntfsmount.log`

只读诊断（无盘也可跑，不挂载、不装助手）：

```bash
./scripts/ntfsmount diagnose
./scripts/ntfsmount diagnose --json
```

提交 Issue 时附上人读输出或 JSON。CI 的 UnitTest 会以 `continue-on-error` 打一份 `--json` 日志。诊断须含「驱动版本校验」：捆绑 `ntfs-3g --version` 仅 2026.7.7 与 2026.8.x 为已测试；未知版本警告风险，仍可继续挂载。

## 安装与 Gatekeeper

- [ ] 未公证 DMG：双击被拦截 → Control-click 打开，或「系统设置 → 隐私与安全性 → 仍要打开」；仍隔离则 `xattr -d com.apple.quarantine /Applications/NTFSMount.app`
- [ ] 首次启动只有**一个**确认框（条款 + 未公证说明 + 助手安装提示）；回车是「同意并继续」，Esc 是「退出」
- [ ] 同意后出现主窗口；空状态写明关窗后菜单栏图标仍在。兼容性/诊断在「设置 → 高级」或「诊断环境…」
- [ ] **助手缺失横幅**：设置里「卸载挂载助手」后（或从未安装），主窗口顶部仍显示同一横幅；菜单挂载项灰掉
- [ ] 未公证：安装助手走管理员密码；安装后没有 `/etc/sudoers.d/ntfs-rw`
- [ ] 已公证（若有）：优先系统服务授权，失败才要密码
- [ ] **菜单栏悬停**：不打开窗口，悬停 **NTFS** 图标能看到卷名 / `NTFS • …` / `diskNsM` / 用量；无盘时为「没有检测到 NTFS」一类文案
- [ ] **关窗 ≠ 退出**：关掉主窗口后菜单栏图标仍在；从程序坞退出后图标消失
- [ ] **诊断环境…**：立刻出现可滚动窗口（先显示「正在检查…」），Copy 只写剪贴板、不再反复弹 Alert

## 真盘

准备：一块外置 NTFS；可选一块 Windows 休眠/快速启动未关的盘；不要用 Boot Camp 当自动挂载对象。

- [ ] 插入外置 NTFS → 自动可写（须已同意首次可写确认）
- [ ] 菜单栏状态为「可写」；访达可拷贝文件
- [ ] 「推出（可安全拔出）」与「卸载」悬停说明不同
- [ ] **占用中推出**：访达打开该盘时点「推出」→ busy 文案，未误弹出
- [ ] 系统 NTFS 只读：子菜单「以可写方式挂载」成功后变可写
- [ ] **全部以可写方式挂载**：脏盘/休眠会弹出与单盘相同的健康框；回车默认只读；不静默 ntfsfix
- [ ] 脏盘 / 休眠：状态为「只读 · 休眠/未正常关机」；不要静默清 hiberfile
- [ ] **挂载前健康检查**：手动可写前「正在检查磁盘健康…」。脏卷回车默认「以只读挂载」；休眠盘无 ntfsfix
- [ ] 脏卷（无休眠文件）：「尝试修复脏卷…」，回车默认「取消」
- [ ] 内置 / Boot Camp：**不会**自动挂载；手动可写有确认框
- [ ] **可能加密 / BitLocker 线索**：空状态橙色提示；格式化框有警告，不得静默抹盘

## 平台（Intel 拒绝）

- [ ] **Intel Mac（x86_64）**：打开 `.app` 出现「无法运行 NTFS 读写」并说明不支持 Intel，仅「退出」；进程退出。勿在此平台做其余真盘项（构建脚本 `scripts/build.sh` / `prepare-runtime.sh` 亦应拒绝 x86_64）

## 格式化（外置整盘，会抹盘）

- [ ] **卷子菜单里没有**「格式化为 NTFS」；只在根菜单「抹掉整盘为 NTFS…」
- [ ] 确认框当前名 / 新卷名分栏，不重叠；回车默认「取消」（两步都只按 Return 不应抹盘）
- [ ] 输错卷名拒绝；输对后还有一次「最后确认」
- [ ] 内置盘格式化不可用

## 卸载（助手）

窗口 **设置 → 卸载助手** 后执行 `bash scripts/check-helper-gone.sh`，下列路径必须不存在：

- `/var/run/com.bioapple.ntfsmount.sock`
- `/Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist`
- `/Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist`
- `/Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd`
- `/Library/Application Support/NTFSMount`
- `/etc/sudoers.d/ntfs-rw`
- `/usr/local/sbin/ntfs-rw-helper`

完全删除应用再用 `./uninstall.sh`，并确认 `/Applications/NTFSMount.app` 已去掉。脚本只移除 NTFSMount 专属组件；系统级 FUSE-T / MacFUSE 以及 `/usr/local/lib/libfuse.2.dylib` 等全局依赖需自行检查。

## 升级

- [ ] 旧版 sudoers 机器打开新包 → 「更新挂载助手」→ 更新后 `check-helper-gone.sh` 里 sudoers 项消失，可写挂载成功
- [ ] 设置无自动检查开关；文案为到 GitHub Releases 手动下载；启动后抓包不应出现 GitHub appcast 请求
- [ ] 菜单无「检查更新…」
- [ ] 当前构建未公证；更新请到 GitHub Releases 手动下载 DMG
