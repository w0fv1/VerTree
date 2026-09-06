---
sidebar_position: 1
---

# Vertree 使用文档

Vertree 是一个面向单文件的桌面版本管理工具。它把设计稿、文档、脚本和配置文件的历史组织成版本树，通过自动监控保留保存记录，并让你直接预览不同版本的内容。

每个备份都是普通文件副本。即使不运行 Vertree，你仍然可以用原来的软件打开这些文件。

## 从这里开始

| 你想做什么 | 阅读哪一页 |
| --- | --- |
| 下载软件、升级到新版本 | [安装与升级](tutorial-usage/install.md) |
| 留下阶段版本、从旧版本继续修改 | [备份、监控与版本树](tutorial-usage/usage.md) |
| 查看文件内容、确认支持哪些格式 | [文件预览与格式支持](tutorial-usage/preview.md) |
| 设置 Windows 右键菜单、用命令行启动 | [右键菜单与命令行](tutorial-usage/entry-points.md) |
| 把某个版本发给同一网络的设备 | [局域网分享](tutorial-usage/sharing.md) |
| 解决预览、菜单或监控问题 | [常见问题](tutorial-usage/troubleshooting.md) |
| 修改应用或 Office Viewer | [开发与构建](tutorial-develop/develop.md) |
| 用脚本查询状态和执行操作 | [本机 API 与开发控制器](tutorial-develop/local-api.md) |

## 1.1.0 的主要变化

- **文件预览**：从版本树节点、Windows 右键菜单或命令行打开文件，不需要先添加监控任务。
- **更多格式**：办公文档、PDF、图片、音视频、电子书、邮件、压缩包，以及 Parquet、Java class 等；PPTX、PSD 和 XMind 提供可视化预览。
- **大文件支持**：取消固定的 64 MiB 预览上限，部分格式按需分段读取。实际能力仍取决于文件结构、解析器和可用资源。
- **更简洁的操作**：打开新预览时关闭上一个；未知格式仅识别文本或显示不支持；移除重复标题、多余说明和版本树外层边框。

完整变化见 [V1.1.0 发布说明](https://github.com/w0fv1/VerTree/releases/tag/V1.1.0)。

## 三种保留与查看文件的方式

| 功能 | 用途 | 文件存放方式 |
| --- | --- | --- |
| 手动备份 / 快速备份 | 给交付稿、方案或阶段成果留档 | 原目录中的独立版本文件，版本和备注写入文件名 |
| 自动监控 | 在持续编辑期间保留保存记录 | 原文件旁的 `*_bak` 目录，按数量上限清理旧备份 |
| 文件预览 | 查看当前文件或历史版本的内容 | 读取临时快照，不修改原文件，也不创建版本节点 |

建议先选一个文件做一次手动备份，再按需要开启监控。预览支持范围不限制备份范围：文件不能预览时，仍可用原软件打开并继续备份。

## 平台差异

| 功能 | Windows | macOS | Linux |
| --- | --- | --- | --- |
| 版本树、手动备份、文件监控 | 支持 | 支持 | 支持 |
| 文件预览 | 应用内 WebView2 | 应用内 WKWebView | 本机浏览器 |
| 系统文件入口 | 传统右键菜单、Windows 11 新菜单 | Finder Services | GNOME Files 扩展 |
| 托盘 / 菜单栏 | 系统托盘 | 菜单栏 | 取决于桌面环境与托盘扩展 |
| 发布包 | EXE、ZIP、MSI、MSIX | 按架构提供 ZIP、DMG | x64 TAR.GZ、DEB、RPM |

macOS 和 Linux 的细节分别见 [macOS 说明](macos.md)和 [Linux 说明](linux.md)。系统菜单提供的动作不完全相同，预览入口以[入口说明](tutorial-usage/entry-points.md)为准。
