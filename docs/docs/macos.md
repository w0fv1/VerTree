---
title: macOS 使用说明
description: 安装 macOS 应用，了解 Finder Services、菜单栏与 WKWebView 的平台差异。
sidebar_position: 20
---

# macOS 使用说明


macOS 提供版本树、手动备份、文件监控、应用内预览和菜单栏入口。Windows 的快速删除与解除占用不属于 macOS 当前能力。

## 安装与首次打开

从[下载页](/download)选择匹配设备架构的 DMG 或 ZIP。3.0.0 提供 arm64 构建；不要把 arm64 包当作 Intel 原生包。将应用放到“应用程序”，再启动一次。

当前发布流程未进行 Apple 公证。首次打开可能需要系统确认；不要为了运行应用关闭全局安全检查。安装包包含预览资源，普通使用不需要 Flutter 或 Node.js。

## Finder Services

Finder 的服务入口提供备份、快速备份、监控和查看版本树。操作会唤起应用，已运行时转交现有实例。未出现时检查应用是否已启动过及系统服务设置。

预览从版本树节点或 `vertree preview "文件路径"` 打开，没有与 Windows 完全相同的菜单单项列表。

## 预览、菜单栏与运行状态

预览使用系统 WKWebView，不需要 WebView2。打开新的应用内预览会结束上一个会话；格式边界见[预览指南](tutorial-usage/preview.md)。

隐藏窗口到菜单栏不等于退出，监控可以继续运行。完全退出后停止监控。“启动后隐藏到托盘 / 菜单栏”仅对自启动触发生效，手动打开仍显示主窗口。主题、语言和监控参数从“设置”调整。

## 从源码运行

需要 Flutter、Xcode、CocoaPods、Python 3 与 Node.js 24。先克隆并初始化子模块，再执行：

```bash
flutter config --enable-macos-desktop
python tools/build_office_preview.py
flutter pub get
flutter run -d macos
```

`macos/build_macos_release.sh` 生成发布工件。构建目录在 iCloud 同步位置时，文件拷贝或签名可能受影响；优先用普通本地目录验证。完整流程见[开发与构建](tutorial-develop/develop.md)。

这轮视觉与文档审计在 Windows 上执行，不替代 macOS 的原生 Services、签名或 WebView 验收。
