---
sidebar_position: 1
---

# 安装与升级

从 [GitHub Releases](https://github.com/w0fv1/VerTree/releases/latest) 下载最新正式版。安装包已包含文件预览资源；普通使用不需要安装 Flutter、Node.js、Python 或 Office-Viewer 的独立应用。

## 选择下载文件

| 平台 | 常规使用 | 其他下载 |
| --- | --- | --- |
| Windows x64 | `vertree-windows-x64-<version>-setup.exe` | `.zip` 为便携版，`.msi` 为另一种安装包 |
| macOS | `vertree-macos-<arch>-<version>.dmg` | `.zip` 为应用归档；按设备和发布页提供的架构选择 |
| Linux x64 | Debian / Ubuntu 选 `.deb`，RPM 系统选 `.rpm` | `.tar.gz` 为便携包 |

`-symbols.zip` 和 `-win11-dev.zip` 用于开发调试，日常安装不需要。MSIX 的签名和应用身份用途见[开发与构建](../tutorial-develop/develop.md#windows)。

## Windows

1. 下载 `setup.exe` 并运行，按向导完成安装。
2. 启动 Vertree，在初始设置中选择需要的右键菜单和开机自启选项。
3. 在资源管理器中右键一个文件，选择“预览文件”或“查看文件版本树”。Windows 11 新菜单中的入口位于 `Vertree` 子菜单内。
4. 需要调整入口时，打开 Vertree 设置页。传统菜单可逐项开关，也可折叠到一个子菜单中。

文件预览需要 **Microsoft Edge WebView2 Runtime**。如果预览提示浏览器环境初始化失败，安装或修复该运行时后重新启动 Vertree。

使用便携版时，应将整个 ZIP 解压到固定目录，再启动 `vertree.exe`；请保留同目录中的 DLL 和 `data` 等资源。注册菜单后移动便携目录，需要在设置页重新注册菜单，让入口指向新位置。

Windows 11 新菜单依赖安装时建立的包身份。若新菜单不可用，可以先从“显示更多选项”使用传统菜单，详细排查见[常见问题](troubleshooting.md#windows-右键菜单没有预览文件)。

## macOS

1. 下载与设备匹配的 DMG，打开后将 Vertree 拖入“应用程序”。也可以解压 ZIP 后放入该目录。
2. 启动一次应用，完成设置，再检查 Finder 的“服务”菜单。
3. 在版本树内打开预览。macOS 使用系统 WKWebView，不需要 WebView2。

当前发布流程未进行 Apple notarization，首次打开可能需要按系统提示确认。Finder Services 当前提供备份、快速备份、监控和版本树入口，预览可从应用内打开。

更多菜单栏、Dock 和 Services 行为见 [macOS 说明](../macos.md)。

## Linux

Debian / Ubuntu 下载 DEB 后，通过系统软件安装器打开，或在下载目录执行：

```bash
sudo apt install ./vertree-linux-x64-1.1.0.deb
```

Fedora 等 RPM 系统可使用系统安装器，或执行：

```bash
sudo dnf install ./vertree-linux-x64-1.1.0.rpm
```

便携 TAR.GZ 需要整体解压，并保留包内资源。Linux 预览由本机浏览器显示；请保持 Vertree 的预览对话框打开，关闭后对应页面不能继续读取文件。

GNOME Files 菜单需要 `python3-nautilus`（Debian / Ubuntu）或 `nautilus-python`（Fedora）。GNOME 托盘通常还需要启用 AppIndicator 扩展；菜单和托盘问题见 [Linux 说明](../linux.md)。

## 从旧版本升级

1. 保存正在编辑的文件，并从 Vertree 托盘或菜单中退出应用，避免安装时文件被占用。
2. 安装新版；便携版建议解压到新目录确认可启动，再调整原有快捷方式和菜单入口。
3. 打开设置检查版本、监控任务和菜单选项，再预览一个常用文件。

升级不需要转换已有版本文件。版本树仍从磁盘上的文件重建，配置和日志位置可在设置页打开。

从旧版升级时，已启用传统右键菜单的用户会自动获得预览项；原来全部关闭的用户保持关闭。传统菜单的逐项选择与 Windows 11 新菜单开关分别管理。

## 校验下载

Release 附带 `SHA256SUMS.txt`。需要确认下载完整性时，将文件的 SHA-256 与清单中的同名条目比较：

```powershell
Get-FileHash .\vertree-windows-x64-1.1.0-setup.exe -Algorithm SHA256
```

构建源码和发布流程见[开发与构建](../tutorial-develop/develop.md)。
