---
sidebar_position: 7
---

# macOS 说明

## 当前支持范围

Vertree 的 macOS 版本已经具备桌面可用性，当前覆盖的能力包括：

- 菜单栏 / 托盘图标
- 应用菜单中的常用操作
- Finder Services：
  - 备份文件
  - 快速备份
  - 监控文件
  - 查看版本树
- 开机自启
- 文件监控与自动备份
- 主题、语言、设置页
- 本机 HTTP API 与 OpenAPI 文档

## 发布与分发

仓库中的 GitHub Actions release workflow 会构建 macOS 发布工件：

- `vertree-macos-<arch>-<version>.zip`
- `vertree-macos-<arch>-<version>.dmg`
- `vertree-macos-<arch>-<version>-symbols.zip`（开发调试用）

当前仍有这些限制：

- 尚未进行 Apple notarization
- 首次打开可能需要用户手动确认
- 如果项目位于 iCloud 同步目录，签名或拷贝阶段可能失败

## 运行方式

以下是源码运行步骤，需要 Flutter、Python 3、Node.js 24 和 Xcode。直接安装 DMG / ZIP 时不需要这些开发工具。

```bash
flutter config --enable-macos-desktop
brew install cocoapods
python tools/build_office_preview.py
flutter pub get
flutter run -d macos
```

## 文件预览

版本树节点可直接打开只读预览，使用 macOS 的 WKWebView，不需要 Windows 的 WebView2。打开另一个文件会关闭上一个应用内预览。

Finder Services 当前提供下述四项动作，尚未增加独立预览项。可以从版本树进入预览，或调用 CLI 的 `preview` 动作。支持格式与排版边界见[文件预览](tutorial-usage/preview.md)。

## Finder Services 的行为

当你在 Finder 中对文件执行 Vertree 服务时，应用会被唤起并把动作转发到 Flutter 层。当前支持：

- `备份文件（Vertree）`
- `快速备份（Vertree）`
- `监控文件（Vertree）`
- `查看版本树（Vertree）`

如果应用已经在后台运行，这些动作会直接复用现有实例。

## 菜单栏与 Dock

- 应用支持隐藏到菜单栏后继续运行
- 从菜单栏恢复窗口时会主动刷新 Dock 图标和激活状态
- 设置页和常用动作可以从应用菜单直接进入
- 开机自启通过原生 channel 接入，不依赖手动编写登录项文件
- “启动后进入托盘 / 菜单栏” 仅对开机自启触发的启动生效，手动打开时会直接显示主界面

## 使用建议

- 首次运行后先确认 Services 是否已经出现在 Finder 中
- 如果项目目录在 iCloud Desktop/Documents 下，优先移走再构建
- 如果只想后台监控，可以在设置页开启启动后进入托盘 / 菜单栏
- 如果要做自动化验证，可直接使用设置页中的本机 HTTP API 文档入口
