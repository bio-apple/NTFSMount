# NTFS 读写

macOS 自带 NTFS **只能读**。本应用把 **ntfs-3g + FUSE 用户态栈** 全部打进 `NTFSMount.app`，无需内核扩展，也无需日常依赖系统里的 FUSE-T。

**日常怎么用 → 见 [操作说明.md](./操作说明.md)**

## 安装 / 卸载

```bash
cd ~/Desktop/bio-apple/NTFSMount
./install.sh    # 首次或重装（含捆绑依赖）
./uninstall.sh
```

`install.sh` 仍会要一次管理员密码：安装 `/usr/local/sbin/ntfs-rw-helper`（开磁盘设备需要）。

## 开发：刷新捆绑二进制

```bash
./scripts/prepare-runtime.sh   # 从系统拷贝/改写 runtime/
./scripts/build.sh             # 打进 dist 或 /tmp 的 .app
```
