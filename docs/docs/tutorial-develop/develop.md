---
sidebar_position: 1
---

# Vertree 开发入门

Vertree 是一个基于 Flutter 的桌面应用，目标是给“单文件持续演进”的工作流提供版本树、自动备份、平台原生入口和本机自动化接口。

## 技术栈

- Flutter Desktop
- Dart
- Windows / macOS / Linux 原生平台桥接
- Docusaurus 文档站

## 环境准备

### Flutter

请先安装 Flutter stable，并确认桌面支持已启用：

```bash
flutter doctor
flutter config --enable-windows-desktop
flutter config --enable-macos-desktop
flutter config --enable-linux-desktop
```

### 平台依赖

- Windows：如需构建安装包，额外安装 Inno Setup 和 WiX Toolset
- macOS：安装 CocoaPods
- Linux：安装 GTK / 通知 / 托盘 / RPM / DEB 打包相关依赖
- 文档站：Node.js 18+

## 克隆项目

```bash
git clone https://github.com/w0fv1/vertree.git
cd vertree
flutter pub get
```

## 运行应用

### Windows

```bash
flutter run -d windows
```

如果你想以前台模式直接联调本地分享页：

```bash
python tools/dev_run.py --device windows --local-docs
```

如果你要验证注册表菜单、Win11 新菜单或开机自启，可能需要提升权限；普通 UI 和版本树/监控逻辑不要求始终以管理员身份运行。

### macOS

```bash
brew install cocoapods
flutter run -d macos
```

### Linux

```bash
flutter run -d linux
```

## 本地开发控制脚本

仓库自带 `dev_server.py`，它会托管一个 `flutter run` 子进程，并暴露 loopback-only 控制接口，方便本地代理或自动化工具迭代 UI：

```bash
python dev_server.py --bootstrap --device windows
```

如果你要给文档截图、录屏或自动化演示准备一个不会弹公告的实例：

```bash
python dev_server.py --bootstrap --device windows --app-arg --no-announcement
```

如果你正在联调局域网分享页，也可以顺手启动本地 docs，并让应用里生成的分享链接直接指向本地文档站：

```bash
python dev_server.py --bootstrap --device windows --local-docs
```

默认会把本地分享页挂到 `http://127.0.0.1:33030/f`，并通过 `dart-define` 注入到应用里的 `LanFileShareServer`。

默认控制器地址为 `http://127.0.0.1:32500`，支持：

- `GET /status`
- `GET /logs`
- `POST /start`
- `POST /reload`
- `POST /hot-restart`
- `POST /restart-process`
- `POST /stop`
- `POST /ensure-ready`

应用自己的本机 HTTP API 默认起始端口为 `31414`，除了监控/备份/版本树接口外，现在还支持：

- `POST /api/v1/app/quit`：退出当前桌面应用
- `POST /api/v1/ui/navigation`：切换到 `brand`、`monitor`、`settings`、`version-tree`
- `POST /api/v1/ui/window-state`：控制窗口还原、最大化与全屏
- `POST /api/v1/ui/theme-mode`：切换主题为 `system`、`light`、`dark`
- `POST /api/v1/ui/file-tree/viewport`：让版本树画布自动适配或按比例缩放
- `POST /api/v1/ui/screenshot`：将当前应用 UI 导出为 PNG
- `GET /api/v1/file-shares`：列出当前进程内仍然有效的局域网分享
- `POST /api/v1/file-shares`：为某个文件创建临时局域网下载分享
- `GET /api/v1/file-shares/{token}`：读取单个局域网分享详情
- `DELETE /api/v1/file-shares/{token}`：撤销临时局域网分享

其中局域网分享能力由一个独立的临时 HTTP 服务承载，默认起始端口为 `31424`，会自动绑定本机 RFC1918 IPv4 接口。它只暴露受分享键保护的下载、探活和信息接口，真正的分享入口由文档站分享页 `https://vertree.w0fv1.dev/f` 承接。当前默认分享格式是 `/f#<payload>`；其中 `payload` 由 `shareKey` 长度标记、Base62 `shareKey`、以及“RFC1918 私网序号列表排序去重后再做差分 + ULEB128 + Base62 外层”的整体编码串联而成。

## 项目结构

```text
vertree/
├── lib/
│   ├── api/            # 本机 HTTP API 契约、文档与 server
│   ├── component/      # 配置、日志、命令处理、窗口控制、托盘等通用组件
│   ├── core/           # 版本树、监控、Result、TreeBuilder 等核心逻辑
│   ├── platform/       # Windows / macOS / Linux 平台集成与 bootstrap
│   ├── service/        # 面向 API 的业务服务
│   ├── view/           # 页面、模块与可视化组件
│   ├── app_runtime.dart
│   └── main.dart
├── windows/            # Windows 打包与上下文菜单相关脚本
├── macos/              # macOS 构建脚本与原生桥接
├── linux/              # Linux 发布与 RPM 打包脚本
├── docs/               # Docusaurus 文档站
└── .github/workflows/  # Release / Pages 工作流
```

## 关键模块

- `lib/main.dart`：按平台选择 bootstrap
- `lib/app_runtime.dart`：应用启动总控、页面切换、单实例、托盘、HTTP API、命令行分发
- `lib/component/app_cli.dart`：CLI 参数解析
- `lib/component/app_command_handler.dart`：把 CLI 请求分发到备份 / 监控 / 版本树动作
- `lib/core/FileVersionTree.dart`：版本号、文件元信息、文件节点与备份/分支逻辑
- `lib/core/MonitManager.dart`、`lib/core/Monitor.dart`：监控任务管理与自动备份
- `lib/api/LocalHttpApiServer.dart`、`lib/service/LocalHttpApiService.dart`：本机自动化接口
- `lib/service/LanFileShareServer.dart`：局域网临时分享服务与 token 下载映射
- `lib/platform/platform_integration.dart`：跨平台上下文菜单、开机自启、GNOME 检测、Win11 包身份等封装

## 构建发布工件

### Windows

```powershell
pwsh -File windows/build.ps1 -BuildMode Release
```

会生成：

- `windows/vertree-windows-x64-<version>-setup.exe`
- `windows/vertree-windows-x64-<version>.zip`
- `windows/vertree-windows-x64-<version>.msi`
- `windows/vertree-windows-x64-<version>-symbols.zip`
- `windows/vertree-windows-x64-<version>-win11-dev.zip`

Windows 11 一级右键菜单使用 sparse MSIX 提供应用身份。面向新设备发布时，构建前需要提供受信任证书：

```powershell
$env:VERTREE_MSIX_CERTIFICATE_PATH="C:\path\to\certificate.pfx"
$env:VERTREE_MSIX_CERTIFICATE_PASSWORD="<password>"
pwsh -File windows/build.ps1 -BuildMode Release
```

如需本地额外生成 unsigned `msix`，可在构建前设置环境变量 `VERTREE_ENABLE_UNSIGNED_MSIX=1`；这只适合开发调试，不适合 clean Windows 11 终端设备。

### macOS

```bash
macos/build_macos_release.sh
```

会生成：

- `build/dist/vertree-macos-<arch>-<version>.zip`
- `build/dist/vertree-macos-<arch>-<version>.dmg`
- `build/dist/vertree-macos-<arch>-<version>-symbols.zip`

### Linux

```bash
linux/build_linux_release.sh
linux/build_linux_deb.sh
linux/build_linux_rpm.sh
```

会生成：

- `build/dist/vertree-linux-x64-<version>.tar.gz`
- `build/dist/vertree-linux-x64-<version>.deb`
- `build/dist/vertree-linux-x64-<version>.rpm`

## 文档站

文档站位于 `docs/`：

```bash
cd docs
npm install
npm start
npm run build
```

如果你要同步更新文档截图，可以直接在仓库根目录运行：

```bash
python tools/update_doc_images.py
```

这个脚本会通过开发控制器调用 `POST /ensure-ready`，然后使用应用本机 HTTP API 的 `ui/navigation` 和 `ui/screenshot` 自动更新 `docs/static/img/usage/` 下的图片。
除专门说明暗色模式的图片外，脚本会先把应用切到浅色主题，再执行截图。

## 版本发布流程

1. 修改 `pubspec.yaml` 中的版本号
2. 同步更新应用内展示版本号（当前在 `lib/app_runtime.dart`）
3. 新建 `.github/release-<version>.md`
4. 更新 README、文档站和必要的站点首页内容
5. 如果需要发布站点公告，同步更新 `docs/static/announcement.json`
   `link` 是可选字段；只有填入合法的 `http/https` 绝对地址时，应用里才会显示“前往”按钮
6. 如有界面变更，执行 `python tools/update_doc_images.py`
7. 构建并验证：
   - `flutter analyze`
   - `npm run build`（在 `docs/` 下）
8. 提交代码并创建 tag：`V<version>`

如果版本号包含 `-alpha`、`-beta`、`-rc` 等后缀，GitHub Actions 会创建 `prerelease`；像 `0.11.2` 这样的正式版本则会创建正式 Release。
