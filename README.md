# Vertree

Vertree 是一个面向单文件的可视化版本管理工具，适合设计稿、文档、脚本、配置文件这类不适合直接放进 Git 工作流的内容。它用树状结构组织版本，用监控机制做自动备份，并通过系统原生入口尽量不改变你原本的使用习惯。

[English README](README.en.md)

![Version tree overview](docs/static/img/version-tree-overview.png)

## 1.0.0 正式版现状

- 支持 Windows 桌面使用，提供安装包、托盘、右键菜单、Windows 11 新菜单适配、监控页、版本树、设置页。
- 支持 macOS 桌面使用，GitHub Release 会生成带架构标识的 `zip` / `dmg` 和符号包，并提供菜单栏/托盘、Finder Services、应用菜单和开机自启。
- 支持 Linux 桌面使用，GitHub Release 会生成便携 `tar.gz`、`.deb` 和 RPM，并提供托盘、GNOME Files 右键菜单、开机自启和设置页集成开关。
- GitHub Actions 会自动构建 Windows、macOS、Linux 三个平台的发布产物。
- 本机 HTTP API 和 OpenAPI 文档已纳入稳定能力，可用于本地自动化测试、监控任务检查、版本树与备份验证。
- 局域网文件分享能力已纳入稳定能力，可为某个版本文件生成局域网短分享链接、二维码和自动选路分享页。
- Windows 11 新设备上的一级右键菜单注册链路已修复，分享页失败探测时的候选地址膨胀已限制。
- 本地开发控制脚本 `dev_server.py` 可托管 `flutter run` 进程并发送 hot reload / hot restart / restart 命令。

## 核心能力

- 树状版本管理：主线版本、分支版本、备注标签都会直接体现在文件名和界面里。
- 自动监控备份：监控文件变化，按配置频率自动写入 `*_bak` 目录，并按数量上限清理旧备份。
- 快速入口：Windows 右键菜单、macOS Finder Services、Linux GNOME Files 右键菜单、托盘菜单、应用菜单都可以直接触发操作。
- 跨平台命令入口：`vertree /path/to/file` 查看版本树，`vertree backup <path>`、`vertree monit <path>`、`vertree express-backup <path>` 直接执行动作。
- 设置集中管理：语言、主题、监控频率、最大备份数、上下文菜单、自启动、本机 HTTP API 都可以在设置页调整。
- 本机自动化接口：提供 loopback-only HTTP API 与 OpenAPI 文档，便于 AI 和脚本验证功能。
- 局域网临时分享：在版本树节点上可直接生成局域网下载分享链接和二维码，接收端可通过浏览器获取文件。
- 单实例与启动优化：避免重复打开，改善启动显示和托盘恢复体验。

## 使用方式

### Windows

1. 到 [GitHub Releases](https://github.com/w0fv1/vertree/releases) 下载最新的 `vertree-windows-x64-<version>.zip`、`vertree-windows-x64-<version>-setup.exe`、`vertree-windows-x64-<version>.msi`，或用于 Win11 菜单调试的 `vertree-windows-x64-<version>-win11-dev.zip`
2. `setup.exe` / `msi` 适合常规安装；`zip` 是真正的便携版，解压后可直接运行 `vertree.exe`
3. Windows 11 一级右键菜单依赖带应用身份的 sparse MSIX；面向新设备发布时需要使用目标设备信任的证书签名
4. 如需 unsigned `msix` 供本地开发调试或后续签名，可在 Windows 本地构建时设置 `VERTREE_ENABLE_UNSIGNED_MSIX=1`
5. 首次启动完成初始化
6. 通过文件右键菜单、托盘或设置页开始使用

### macOS

到 [GitHub Releases](https://github.com/w0fv1/vertree/releases) 下载最新的 macOS `zip` 或 `dmg`，文件名会带上当前构建架构（如 `x64` / `arm64`）。

已支持的 macOS 入口：

- Finder Services：备份、快速备份、监控、查看版本树
- 应用菜单：设置、备份、快速备份、监控、查看版本树
- 菜单栏图标：打开设置、执行常用操作
- 开机自启：通过设置页启用

如需本地构建运行：

```bash
flutter config --enable-macos-desktop
brew install cocoapods
flutter pub get
flutter run -d macos
```

### Linux

到 [GitHub Releases](https://github.com/w0fv1/vertree/releases) 下载：

- `vertree-linux-x64-<version>.tar.gz`：便携发布包
- `vertree-linux-x64-<version>.deb`：Debian / Ubuntu 安装包
- `vertree-linux-x64-<version>.rpm`：RPM 安装包

GNOME 环境下已支持：

- 托盘菜单
- GNOME Files 顶层右键菜单
- 设置页中启用/禁用右键菜单
- 开机自启

如需本地构建：

```bash
flutter config --enable-linux-desktop
flutter pub get
flutter run -d linux
```

### 命令行

```bash
vertree /path/to/file
vertree backup /path/to/file
vertree monit /path/to/file
vertree express-backup /path/to/file
```

## 本机 HTTP API

默认启用的本机 HTTP API 只绑定 `127.0.0.1`，默认起始端口为 `31414`，若被占用会自动递增。

- `GET /api/v1`：接口索引
- `GET /api/v1/openapi.json`：OpenAPI 文档
- `GET /api/v1/docs`：交互式文档
- `GET /api/v1/health`：运行状态
- `POST /api/v1/app/quit`：退出当前 Vertree 应用
- `POST /api/v1/ui/navigation`：切换到指定页面
- `POST /api/v1/ui/window-state`：切换窗口为还原 / 最大化 / 全屏
- `POST /api/v1/ui/theme-mode`：切换主题为 `system` / `light` / `dark`
- `POST /api/v1/ui/file-tree/viewport`：让文件树适配视口或设置缩放比例
- `POST /api/v1/ui/screenshot`：导出当前应用窗口 PNG 截图
- `GET/POST/PATCH/DELETE /api/v1/monitor-tasks`：监控任务管理
- `GET /api/v1/monitor-tasks/{id}/backups`：查看某个监控任务对应的备份文件
- `POST /api/v1/monitor-tasks/{id}/verification-writes`：向监控文件写入内容并验证是否生成新备份
- `POST /api/v1/backups`：触发单次备份
- `GET /api/v1/backups`：列出备份目录文件
- `GET /api/v1/version-files`：列出同一版本族文件
- `GET /api/v1/version-trees`：生成版本树
- `GET/POST/DELETE /api/v1/file-shares`：管理局域网文件分享
- `GET /api/v1/file-shares/{token}`：查看某个局域网分享的详情

用于刷新文档截图时，可以配合本地开发控制器运行：

```bash
python tools/update_doc_images.py
```

它会通过 `POST /ensure-ready` 拉起或复用开发中的应用实例，再调用 `ui/theme-mode`、`ui/navigation` 和 `ui/screenshot` 自动更新截图资源。除专门说明暗色模式的图片外，文档截图默认使用浅色主题。

## 开发运行

### Windows

```bash
flutter config --enable-windows-desktop
flutter pub get
flutter run -d windows
```

如果你想一条命令同时启动本地 docs，并让局域网分享页走本地站点：

```bash
python tools/dev_run.py --device windows --local-docs
```

### macOS

```bash
flutter config --enable-macos-desktop
brew install cocoapods
flutter pub get
flutter run -d macos
```

如果项目位于 iCloud 同步的 `Desktop` 或 `Documents` 下，macOS 可能在签名阶段失败，建议移到非 iCloud 目录。

构建 macOS 发布工件：

```bash
macos/build_macos_release.sh
```

### Linux

```bash
flutter config --enable-linux-desktop
flutter pub get
flutter run -d linux
```

构建 Linux 发布工件：

```bash
linux/build_linux_release.sh
linux/build_linux_rpm.sh
```

### 开发控制脚本

本地代理或自动化工具可以通过 `dev_server.py` 托管 `flutter run`：

```bash
python dev_server.py --bootstrap --device windows
```

如需给文档截图或自动化演示使用一个不会弹公告的实例：

```bash
python dev_server.py --bootstrap --device windows --app-arg --no-announcement
```

如果你要在开发态顺手启动本地 docs，并让局域网分享页直接指向本地 Docusaurus：

```bash
python dev_server.py --bootstrap --device windows --local-docs
```

这会额外拉起 `http://127.0.0.1:33030/f`，并通过 `dart-define` 把局域网分享页基地址切到本地 docs。

默认控制器地址为 `http://127.0.0.1:32500`，支持：

- `GET /status`
- `GET /logs`
- `POST /start`
- `POST /reload`
- `POST /hot-restart`
- `POST /restart-process`
- `POST /stop`
- `POST /ensure-ready`

## 配置文件

配置保存在应用支持目录下的 `config.json` 中。常用字段包括：

- `locale`
- `themeMode`
- `monitorRate`
- `monitorMaxSize`
- `monitFiles`
- `launch2Tray`
- `isSetupDone`
- `win11MenuEnabled`
- `localHttpApiEnabled`

建议优先通过设置页修改，而不是手动编辑。

## 文档

- 用户文档：[https://vertree.w0fv1.dev/](https://vertree.w0fv1.dev/)
- 局域网分享页：[https://vertree.w0fv1.dev/f](https://vertree.w0fv1.dev/f)
- 本地文档开发：[docs/README.md](docs/README.md)

## 已知限制

- Windows 11 新菜单默认支持安装版直接注册；如果菜单没有立即刷新，可能需要重新启动 Explorer 或重新切换一次设置页开关。
- Linux 下 GNOME Files 右键菜单依赖 `nautilus-python`，GNOME 托盘常常还依赖额外的 AppIndicator 扩展。
- macOS 发布工件目前未做 Apple notarization，首次打开可能需要手动确认。
- 版本树画线和复杂树布局仍有继续优化空间。

## 后续方向

- 更稳定的版本树布局与画布体验
- 更细的权限控制与平台集成
- 文件差异展示、搜索和验证能力

## 许可

MIT. See [LICENSE](LICENSE).
