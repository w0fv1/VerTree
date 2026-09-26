---
title: 安装与升级
description: 按平台选择安装包，了解资源依赖、单配置文件与升级边界。
sidebar_position: 1
---

# 安装与升级


先在[下载页](/download)选择平台，再从 GitHub 发布附件安装。正式包已包含文件预览资源，不需要安装开发工具。

## 选哪个文件

| 平台 | 常规使用 | 其他选择 |
| --- | --- | --- |
| Windows x64 | 文件名以 `-setup.exe` 结尾 | ZIP 便携版、MSI |
| macOS Apple Silicon | 带 `arm64` 的 DMG | ZIP 应用归档 |
| Linux x64 | Debian / Ubuntu 选 DEB，Fedora 等选 RPM | TAR.GZ 便携包 |

具体架构以发布页实际附件为准。`symbols.zip` 和 `win11-dev.zip` 是调试工件，不是普通用户需要安装的组件。MSIX 的签名要求见[Windows 构建说明](../tutorial-develop/develop.md#windows)。

## Windows

运行 EXE 安装程序，完成后启动 Vertree。在“设置”中选择需要的菜单入口、自启动与监控参数，然后对一个测试文件执行备份。Windows 11 的新入口位于资源管理器的 `Vertree` 子菜单，经典入口位于“显示更多选项”。

预览依赖 **Microsoft Edge WebView2 Runtime**。全部格式都无法预览时，先检查这个运行环境，不要通过修改文件扩展名排查。

便携版必须整体解压到固定目录，保留 EXE、DLL、`data` 等资源。注册菜单后移动安装位置，需要重新应用菜单设置。Windows 11 新菜单还依赖包身份注册；没有成功注册时，先使用经典菜单。

3.0.0 中两套菜单均支持逐项设置。旧版本可能只有 Windows 11 总开关，参见[菜单版本区别](entry-points.md)。

## macOS

将 DMG 中的应用拖入“应用程序”，或解压 ZIP 后移动到该目录。第一次启动后再检查 Finder Services。预览使用系统 WKWebView，不需要 WebView2。

当前发布流程未进行 Apple 公证。首次打开按系统提示处理，只安装确认来自项目发布页的文件，不要全局关闭系统安全检查。更多说明见 [macOS](../macos.md)。

## Linux

用系统软件安装器打开 DEB 或 RPM。使用终端时，替换为实际下载的文件名，例如：

```bash
# Debian / Ubuntu；将版本号换成实际下载版本
sudo apt install ./vertree-linux-x64-3.0.0.deb
```

```bash
# Fedora 等 RPM 系统
sudo dnf install ./vertree-linux-x64-3.0.0.rpm
```

便携 TAR.GZ 也需要整体解压。交互预览使用本机浏览器，关闭 Vertree 预览会话后旧页面不能继续读取文件。GNOME Files 与托盘依赖见 [Linux](../linux.md)。

## 升级前后各做什么

保存正在编辑的内容，等待文件操作结束，再完全退出 Vertree 后覆盖安装。安装后检查应用版本、监控任务和所用菜单入口，并试着预览一个小文件。

**从 2.0 以前升级需要重新配置监控。** 当前配置采用 `settings.json`、`monitorTasks` 与任务 UUID。旧 `config.json` 不导入，旧 `*_bak` 备份不自动转为新快照，但磁盘上的手动版本文件仍可识别。3.0.0还会清理固定的旧配置文件名，不保留 `.previous` 配置副本；不会借此删除旧备份内容。

不要把“覆盖安装”当作迁移所有旧设置的保证。配置字段和位置见[设置与配置文件](settings.md)。新功能是否随安装包提供，以对应发布说明为准。

## 核对下载与卸载

将下载文件的 SHA-256 与发布附件 `SHA256SUMS.txt` 中的同名条目对照：

```powershell
Get-FileHash .\vertree-windows-x64-3.0.0-setup.exe -Algorithm SHA256
```

卸载前先退出应用，再使用对应安装器的卸载入口。多个安装器留下多个记录时，不要假定它们指向不同目录；先核对路径，避免另一份卸载器移除仍在使用的程序。用户文件与备份的保留应单独检查。

下一步：[完成第一次备份](quick-start.md)。
