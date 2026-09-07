# Vertree

Vertree 是面向单文件的桌面版本管理工具：用版本树保留主线与分支，通过文件监控自动备份，并直接预览文档、图片、媒体和历史版本。每个版本都是普通文件副本，可以继续用原来的软件打开。

[English](README.en.md) · [使用文档](https://vertree.w0fv1.dev/docs/intro) · [下载正式版](https://github.com/w0fv1/VerTree/releases/latest) · [格式支持](docs/docs/tutorial-usage/preview.md) · [常见问题](docs/docs/tutorial-usage/troubleshooting.md)

## 2.0.0 更新

- 统一版本命令与写入协调，明确版本、快照、监控和 UI 的职责。
- 自动快照按任务 UUID 隔离，只清理归属验证通过的快照；监控失败重试并保留后续变化。
- 修复 Windows MSI 快捷方式目录，并在发布前验证安装与卸载。
- **不兼容升级**：使用新的 settings.json，旧配置与旧 *_bak 不自动导入；本机 API 改用 /versions 和 /snapshots。升级后请重新配置监控。

[完整发布说明](https://github.com/w0fv1/VerTree/releases/tag/V2.0.0) · [架构与扩展规则](docs/architecture-evolution.md)

## 下载与开始使用

| 平台 | 常规下载 | 预览方式 |
| --- | --- | --- |
| Windows x64 | `vertree-windows-x64-<version>-setup.exe`；便携版 `.zip` | 应用内 WebView2，需要 WebView2 Runtime |
| macOS | 带架构标识的 `.dmg` / `.zip` | 应用内 WKWebView |
| Linux x64 | `.deb` / `.rpm` / `.tar.gz` | 本机浏览器 |

Windows 另提供 MSI、MSIX 和调试工件；macOS 当前发布流程未进行 Apple notarization。Linux 的 Files 菜单和托盘依赖桌面环境。安装包已经包含预览资源，普通用户无需安装开发工具或独立 Office-Viewer。

1. 安装并启动 Vertree，在设置中选择需要的系统菜单与自启动选项。
2. 对一个常用文件执行“备份文件”或“快速备份”，保留阶段成果。
3. 打开版本树，预览历史节点，按需要继续创建版本或分支。
4. 对持续编辑的文件开启监控，在 `*_bak` 目录保留自动备份；默认最小间隔 5 分钟，每任务最多保留 50 份。

详细步骤见[安装与升级](docs/docs/tutorial-usage/install.md)、[备份与监控](docs/docs/tutorial-usage/usage.md)、[右键菜单](docs/docs/tutorial-usage/entry-points.md)。

## 命令行

```bash
vertree "文件路径"
vertree preview "文件路径"
vertree backup "文件路径"
vertree express-backup "文件路径"
vertree monit "文件路径"
vertree share "文件路径"
```

每次处理一个文件。若未加入 PATH，请使用可执行文件的完整路径；Windows PowerShell 在当前目录使用 `.\vertree.exe`。

## 本机与局域网功能

- **预览**：本机临时快照与离线页面，关闭会话后清理，不上传文件，不执行宏或文件脚本。
- **局域网分享**：主动为某个文件创建临时链接或二维码，同网设备直接从发送端下载。
- **本机 API**：默认关闭，启用后仅监听 loopback；起始端口 31414，占用时递增。业务请求需要本次启动的 Bearer Token，索引、文档和最小探活不需要。

三个服务独立管理。详见[局域网分享](docs/docs/tutorial-usage/sharing.md)、[本机 API](docs/docs/tutorial-develop/local-api.md)。

## 源码构建

需要 Flutter stable（Dart `>=3.10.0 <4.0.0`）、Python 3、Node.js 24 和目标平台桌面工具链。Windows 还需要 Visual Studio 2022、NuGet CLI；macOS 需要 Xcode 与 CocoaPods。

```bash
git clone https://github.com/w0fv1/VerTree.git
cd VerTree
git submodule update --init vendor/office-viewer
python tools/build_office_preview.py
flutter pub get
flutter run -d windows
```

在相应平台将设备名换为 `macos` 或 `linux`。首次 Flutter 构建前必须生成预览资源；前端改动后重新构建并 hot restart，原生改动需要完整重启。

Office-Viewer 的 React 预览模块作为 Flutter assets 打包；Vertree 不运行 Tauri 进程。通用格式能力在 [Office-Viewer](https://github.com/w0fv1/Office-Viewer) 仓库维护，先推送上游提交，再更新本仓库子模块指针。

[开发与构建](docs/docs/tutorial-develop/develop.md) · [预览架构](docs/docs/tutorial-develop/preview-architecture.md) · [开发控制器](docs/docs/tutorial-develop/local-api.md) · [文档站维护](docs/README.md)

## 验证与限制

```bash
flutter analyze
flutter test
npm --prefix web/office_preview test
npm --prefix docs run build
```

预览不能完整还原所有专有格式。旧 DOC/PPT、MSG、MOBI/AZW 和加密电子书尚无专用支持，音视频解码取决于系统浏览器。支持某个扩展名也不代表该格式的所有特性都已实现，具体见[格式矩阵](docs/docs/tutorial-usage/preview.md)。

## 许可

Vertree 使用 MIT 许可，见 [LICENSE](LICENSE)。随包预览依赖保留各自的许可与第三方声明。
