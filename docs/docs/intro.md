---
title: 从一个文件开始
description: 按任务查找 Vertree 的安装、版本树、监控、预览与 Windows 文件工具指南。
sidebar_position: 1
---

# 从一个文件开始


**让每一次迭代都有迹可循。** Vertree 用普通文件副本保留阶段成果，用版本树表达主线与分支。文件仍交给原软件编辑，不必先学会一套协作仓库流程。

<div className="vt-doc-grid">
<a className="vt-doc-card" href="/docs/tutorial-usage/quick-start"><strong>完成第一次备份</strong><span>选一个文件，保存一份带备注的版本，再打开版本树。</span></a>
<a className="vt-doc-card" href="/docs/tutorial-usage/install"><strong>安装与升级</strong><span>选择适合平台的安装包，确认升级注意事项。</span></a>
<a className="vt-doc-card" href="/docs/tutorial-usage/monitoring"><strong>让变化自动留档</strong><span>设置监控间隔、快照上限与任务状态。</span></a>
<a className="vt-doc-card" href="/docs/tutorial-usage/preview"><strong>检查文件内容</strong><span>查看支持格式、只读预览与大文件限制。</span></a>
</div>

## 先分清三种用途

| 功能 | 什么时候使用 | 文件在哪里 |
| --- | --- | --- |
| 手动版本 | 交付、评审、切换方案前保留一个节点 | 原目录，版本号与备注进入文件名 |
| 自动快照 | 持续编辑时按变化留档 | 源目录下的 `.vertree/snapshots/<任务 UUID>` |
| 文件预览 | 先查看内容，再决定如何处理 | 本机临时快照，关闭会话后清理 |

手动版本不会被监控的数量上限自动清理。自动快照不是每次保存都有一份；本机副本也不能替代异地备份。

## 按任务继续

需要找回一版或分出另一个方向，阅读[版本树](tutorial-usage/version-tree.md)。需要让其他设备下载文件，阅读[局域网分享](tutorial-usage/sharing.md)。菜单入口、命令行和设置分别见[系统入口](tutorial-usage/entry-points.md)与[设置和配置文件](tutorial-usage/settings.md)。

Windows 3.0.0还提供两个独立功能：[快速删除](tutorial-usage/fast-delete.md)与[解除占用](tutorial-usage/file-locks.md)。一个执行永久删除，另一个查看并处理占用进程，不能混为一谈。

## 文档与下载版本

这套文档对应 **3.0.0**。Windows 文件工具、两套右键菜单逐项设置与新版首页均随此版本提供。旧版界面可能不同，请先在[下载页](/download)核对安装包与[发布说明](https://github.com/w0fv1/VerTree/releases/tag/V3.0.0)。Windows 专有功能不会因此在 macOS 或 Linux 上出现。

## 平台差异

| 功能 | Windows | macOS | Linux |
| --- | --- | --- | --- |
| 版本树、备份、文件监控 | 支持 | 支持 | 支持 |
| 交互预览 | 应用内 WebView2 | 应用内 WKWebView | 本机浏览器 |
| 文件菜单 | 经典菜单、Win11 新菜单 | Finder Services | GNOME Files 扩展 |
| 托盘或菜单栏 | 系统托盘 | 菜单栏 | 取决于桌面环境 |
| 快速删除、解除占用 | 3.0.0 起支持 | 未提供 | 未提供 |

平台安装细节见 [macOS](macos.md)与 [Linux](linux.md)。出现问题先看[排障指南](tutorial-usage/troubleshooting.md)；准备修改源码时，从[开发与构建](tutorial-develop/develop.md)开始。
