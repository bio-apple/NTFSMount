# NTFS 读写 · NTFSMount

[下载](https://github.com/bio-apple/NTFSMount/releases) · [English](#english)

Mac 上给**外置 NTFS 盘**可写访问，不用内核扩展。仅 **Apple Silicon + macOS 13+**，不支持 Intel。

当前是个人使用、未公证预发布（从 [Releases](https://github.com/bio-apple/NTFSMount/releases) 下 `NTFSMount.dmg`，不要用 Latest，不要镜像）。**写 NTFS 可能损坏数据，请先备份。**

**`go-nfsv4` 不是 GPL。作为产品分发或销售前须取得 [FUSE-T](https://www.fuse-t.org/) 书面许可。** 见 [NOTICE](./NOTICE)。

## 使用

1. 下载 DMG，校验：`shasum -a 256 NTFSMount.dmg`（须与 Release 正文一致）。
2. 拖入「应用程序」。若拦截：Control-click → 打开，或「系统设置 → 隐私与安全性」→ 仍要打开。
3. 打开后回车是 **退出**，点 **同意并继续**；再在窗口点 **安装…**（要管理员密码）。
4. 插入外置 NTFS，用访达读写。用完 **推出（可安全拔出）**，盘消失后再拔线。

菜单栏 **NTFS** 点子菜单即可挂载 / 卸载 / 推出，或 **打开窗口**。自动挂载和助手在 **设置**。内置盘不会自动挂。

| 状态 | 做什么 |
| --- | --- |
| 可写 | 直接用 |
| 只读 · 系统 NTFS | 卷干净时，子菜单里改成可写 |
| 只读 · 休眠/未正常关机 | 先在 Windows 彻底关机，不要强行可写 |

格式化只对外置整盘：输入当前卷名，回车默认 **取消**。  
卸载助手：设置里。卸掉应用：`./uninstall.sh`。

![主窗口](docs/screenshots/window.png)

## 开发

```bash
./scripts/prepare-runtime.sh   # 需 brew ntfs-3g，以及一次 FUSE-T
swift test && ./scripts/test-helper.sh
./scripts/build.sh && ./scripts/package-dmg.sh
```

真盘步骤：[docs/MANUAL_TEST.md](./docs/MANUAL_TEST.md)。公证与分发：[docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md)。

本仓库 Swift 与 ntfs-3g 为 GPL-2.0-or-later（[LICENSE](./LICENSE)）。`go-nfsv4` 不能按 GPL 再分发。

## English

<details>
<summary>English</summary>

Writable **external** NTFS on Apple Silicon + macOS 13+. No Intel. No kexts. Personal-use, not notarized: download `NTFSMount.dmg` from [Releases](https://github.com/bio-apple/NTFSMount/releases) (not Latest). Do not mirror.

`go-nfsv4` is not GPL; get a written [FUSE-T](https://www.fuse-t.org/) license before shipping as a product. Back up first. UI is Simplified Chinese.

Download → drag to Applications → Control-click Open if blocked → **同意并继续** (Return is Quit) → **安装…** → plug in disk → **推出（可安全拔出）** before unplugging. Hibernated/dirty volumes stay read-only.

Build: `./scripts/prepare-runtime.sh && ./scripts/test-helper.sh && ./scripts/package-dmg.sh`. See [NOTICE](./NOTICE).

</details>
