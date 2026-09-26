# Vertree 维树

**让每一次迭代都有迹可循。**

Vertree 是面向单文件的桌面版本管理工具。用普通文件副本保留阶段成果，通过版本树查看主线与分支，按需要开启自动快照、只读预览和局域网分享。编辑仍在原软件里完成。

[English](README.en.md) · [官网](https://vertree.w0fv1.dev/) · [快速开始](docs/docs/tutorial-usage/quick-start.md) · [下载正式版](https://github.com/w0fv1/VerTree/releases/latest) · [常见问题](docs/docs/tutorial-usage/troubleshooting.md)

![Vertree 示例版本树](docs/static/img/version-tree-overview.png)

## 适合怎样使用

| 想做的事 | 使用方式 |
| --- | --- |
| 在评审或交付前留一版 | 手动备份并写备注，文件保存在原目录 |
| 从旧稿试一个新方向 | 在版本树中确认起点，再创建分支 |
| 持续编辑时自动留档 | 监听文件变化，在 `.vertree/snapshots/<任务 UUID>` 内保留快照 |
| 先确认内容，再打开编辑 | 本机只读预览；不支持的格式用原软件打开 |
| 给同网设备发送这一版 | 显式创建临时局域网分享 |
| 接入脚本或验证工具 | 按需启用带认证的 loopback API |

完整副本会占用磁盘空间，本地备份不能替代异地备份。监控默认最小间隔 5 分钟，每任务保留 50 份已识别快照，不承诺每次保存都生成副本。

## 3.0.0：文件工具与体验更新

**V3.0.0** 新增 Windows 快速永久删除与解除占用，统一两套右键菜单的逐项设置，并更新首页、官网与使用文档。两个文件工具彼此独立，仅从文件右键菜单进入；删除必须确认，可能结束可处理的占用程序。完整变化见 [3.0.0 发布说明](https://github.com/w0fv1/VerTree/releases/tag/V3.0.0)。

删除与占用查询是独立页面，仅从文件右键菜单进入。删除一次确认后按授权处理只读和可处理占用，不绕过系统保护；结束进程可能丢失未保存内容。详见[删除指南](docs/docs/tutorial-usage/fast-delete.md)、[占用指南](docs/docs/tutorial-usage/file-locks.md)。

从 2.0 以前升级需要重新配置监控。当前使用 `settings.json`、`monitorTasks` 与 UUID 快照清单，旧 `config.json` 和 `*_bak` 不自动导入。3.0.0 不再保留 `.previous` 配置回退；旧备份内容不因配置清理而自动删除。[配置说明](docs/docs/tutorial-usage/settings.md)

## 安装与开始使用

Windows x64 日常选 `-setup.exe`，macOS 按发布页架构选 DMG，Linux x64 按发行版选 DEB / RPM。便携版整体解压，不能只拷贝一个可执行文件。安装包已包含预览资源，普通使用不需要 Flutter、Node.js 或独立 Office-Viewer。

Windows 预览依赖 WebView2 Runtime；macOS 使用 WKWebView；Linux 使用本机浏览器。Windows 11 菜单依赖包身份，macOS 公证与 Linux 桌面集成各有限制，见[安装与升级](docs/docs/tutorial-usage/install.md)。

先保存一个测试文件，执行备份并填写备注，再打开版本树核对新文件。之后才按需要开启监控。[完整步骤](docs/docs/tutorial-usage/quick-start.md)

## 开发与验证

需要 Flutter stable（Dart 满足 `pubspec.yaml`）、Python 3、Node.js 24 和目标平台桌面工具链。先生成固定子模块的预览资源：

```bash
git clone https://github.com/w0fv1/VerTree.git
cd VerTree
git submodule update --init vendor/office-viewer
python tools/build_office_preview.py
flutter pub get
flutter run -d windows
```

在对应系统将设备名换为 `macos` 或 `linux`。Windows 还需要 Visual Studio C++ 工具链、Windows SDK 与 NuGet。Vertree 复用 Office-Viewer 的 React 模块，不启动其 Tauri 进程。

```bash
dart run tools/check_architecture.dart
flutter analyze
flutter test
npm --prefix docs ci
npm --prefix docs run build
npm --prefix docs run audit:static
```

浏览器逐页验证、截图和发布流程见[站点维护](docs/README.md)，原生删除测试见[实现说明](docs/windows-file-tools.md)。测试只在专用数据和测试进程上执行，不拿用户文件做删除基准。

[开发与构建](docs/docs/tutorial-develop/develop.md) · [架构约束](docs/architecture-evolution.md) · [本机 API](docs/docs/tutorial-develop/local-api.md) · [格式支持](docs/docs/tutorial-usage/preview.md)

## 许可

Vertree 使用 MIT 许可，见 [LICENSE](LICENSE)。随包第三方组件保留各自的许可与声明。预览不保证所有专有格式的完整排版，不提供云同步或多人合并。
