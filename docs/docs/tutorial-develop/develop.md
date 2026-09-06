---
sidebar_position: 1
---

# 开发与构建

Vertree 是 Flutter 桌面应用。文件预览复用独立仓库 Office-Viewer 的 React 前端，打包为 Flutter assets；没有在 Flutter 中嵌入 Tauri 进程。

## 环境准备

| 环境 | 要求 |
| --- | --- |
| 通用 | Git、Python 3、Node.js 24、Flutter stable（Dart 满足 `>=3.10.0 <4.0.0`） |
| Windows | Visual Studio 2022 桌面 C++ 工具链、Windows SDK、CMake、PATH 中的 NuGet CLI；运行预览需要 WebView2 Runtime |
| Windows 打包 | Inno Setup、WiX Toolset；MSIX 使用 Windows SDK 的 MakeAppx / SignTool |
| macOS | Xcode、CocoaPods |
| Linux | Clang、CMake、Ninja、pkg-config、GTK3、通知和托盘开发库；打包还需要 RPM、desktop-file-utils、appstream |

在目标操作系统上运行 `flutter doctor` 检查桌面工具链。三平台具体 CI 依赖以仓库的 `.github/workflows/release.yml` 为准。

Windows 发布固定使用 `windows-2022` runner。现有 WebView 插件仍使用实验性协程接口，更新的 MSVC 工具链会报 STL1011；升级编译器前应先验证插件兼容性。

## 首次克隆与启动

```bash
git clone https://github.com/w0fv1/VerTree.git
cd VerTree
git submodule update --init vendor/office-viewer
python tools/build_office_preview.py
flutter pub get
flutter run -d windows
```

在 macOS 或 Linux 上，将最后一行设备名改为 `macos` 或 `linux`，并按需执行 `flutter config --enable-macos-desktop` 或 `flutter config --enable-linux-desktop`。

**第一次 Flutter 构建之前必须生成预览资源。** Python 脚本会初始化固定版本的 Office-Viewer 子模块，用 `web/office_preview/package-lock.json` 安装依赖，再构建离线资源。无须安装上游 Tauri/Rust 工具链，也无须初始化其仅作参考的 `vendor/vscode-office` 子模块。

## 修改后如何更新

| 改动 | 操作 |
| --- | --- |
| 普通 Dart 布局与样式 | Flutter hot reload |
| Dart 初始化、路由注册 | hot restart |
| 原生插件、Windows COM 菜单、启动行为 | 完整重新构建并重启应用进程 |
| Office-Viewer 解析器或嵌入前端 | 重新运行 `python tools/build_office_preview.py --skip-install`，再 hot restart |
| 前端依赖或 lockfile | 不加 `--skip-install` 重新构建 |

不要把生成资源与 Flutter 测试并行运行：Vite 会先清空输出目录，测试可能恰好读到缺失的 assets。

## 两个仓库如何协作

`vendor/office-viewer` 是固定提交的 Git 子模块。通用格式注册、解析器、渲染器和样例在 Office-Viewer 维护；Vertree 负责只读入口、会话服务、WebView 与系统菜单。

更新步骤：

1. 在 Office-Viewer 修改并验证通用预览能力，提交到该仓库。
2. 检查新增运行时依赖，并同步到 Vertree 的 `web/office_preview/package.json` 和 lockfile。
3. 在 Vertree 重建预览资源，验证新格式与现有格式。
4. 先推送 Office-Viewer 提交，再提交并推送 Vertree 的子模块指针，否则干净 CI 无法获取该提交。
5. 用独立检出目录验证构建，避免子模块本地 `node_modules` 掩盖遗漏的依赖或类型映射。

宿主的 TypeScript 路径与 Vite dedupe 配置使用宿主依赖。带 `exports` 的包子路径需正确解析，例如 `heic-to/csp` 需要映射到对应的类型入口。详见[预览架构](preview-architecture.md)。

## 关键目录

| 路径 | 职责 |
| --- | --- |
| `lib/core` | 文件版本、树构建、监控与备份 |
| `lib/view` | 页面、节点操作、预览对话框 |
| `lib/component/app_cli.dart` | CLI 动作解析 |
| `lib/platform` | 系统菜单、自启动等平台集成 |
| `lib/api`、`lib/service` | 本机 API、业务服务、局域网分享与预览会话 |
| `vendor/office-viewer` | 通用预览源码子模块 |
| `web/office_preview` | Vertree 的只读 React 宿主及依赖锁定 |
| `assets/office_viewer` | 构建生成的离线资源，生成内容不入 Git |
| `test` | Flutter 回归测试 |
| `.sample/file_version_tree` | 版本树与监控的标准示例 |
| `docs` | Docusaurus 站点、用户指南、开发文档 |

## 验证

已有预览资源后，在仓库根目录运行：

```bash
flutter analyze
flutter test
npm --prefix web/office_preview test
```

修改 Office-Viewer 时，在其 `office-viewer-app` 目录安装依赖并执行 `npm test`、`npm run lint`、`npm run build`。独立 Tauri 构建只在验证独立应用时需要。

Windows 菜单还有不需要注册系统菜单的原生验证：

```powershell
cmake -S windows/context_menu/tests -B build/context-menu-tests -A x64
cmake --build build/context-menu-tests --config Release
ctest --test-dir build/context-menu-tests -C Release --output-on-failure
```

自动测试和跨平台编译不能代替原生 WebView、Explorer、Finder 等实机验收。预览回归应包括连续打开不同文件、关闭回收、未知文本与二进制、大文件和相应格式的真实样例。

## 构建发布工件

先运行 `python tools/build_office_preview.py`，再执行对应平台脚本。GitHub Release workflow 已包含这个前端步骤。

### Windows

```powershell
pwsh -File windows/build.ps1 -BuildMode Release
pwsh -File windows/build_msix.ps1 -BuildMode Release
```

产物在 `windows/`，文件名前缀为 `vertree-windows-x64-<version>`，包含 EXE 安装器、ZIP、MSI、MSIX 及调试包。

Windows 11 新菜单通过 sparse MSIX 提供包身份。目标设备需要信任签名证书。构建脚本接受 `VERTREE_MSIX_CERTIFICATE_PATH` 和 `VERTREE_MSIX_CERTIFICATE_PASSWORD`，CI 对应使用仓库证书 secrets。未签名包仅适合相应开发流程，不能据此保证新设备的 Win11 菜单注册成功。

### macOS

```bash
macos/build_macos_release.sh
```

产物位于 `build/dist/`，包含按当前构建架构标记的 ZIP、DMG，以及可用时生成的符号包。当前流程不含 Apple notarization。

### Linux

```bash
linux/build_linux_release.sh
SKIP_FLUTTER_BUILD=1 linux/build_linux_deb.sh
SKIP_FLUTTER_BUILD=1 linux/build_linux_rpm.sh
```

产物位于 `build/dist/`，包含 TAR.GZ、DEB、RPM。构建依赖和 GNOME 集成见 [Linux 说明](../linux.md)。

## 文档站

```bash
cd docs
npm ci
npm start
```

提交前执行 `npm run build` 检查链接、MDX 和静态输出。站点由 main 分支的 Pages workflow 构建并部署。仓库当前也跟踪 `docs/build`，更新文档时同步生成产物。

更新应用截图使用仓库根目录的 `python tools/update_doc_images.py`。脚本通过开发控制器和应用 API 导航、调整主题、导出 PNG；应使用由控制器管理的开发进程与标准样例，检查生成画面后再提交。不要把旧截图当作新版界面的验收证据。

控制器启动、热更新和 API 访问示例见[本机 API 与开发控制器](local-api.md)。

## 发布流程

1. 修改 `pubspec.yaml` 中的版本号。应用展示版本从 `PackageInfo` 读取，不需要在 Dart 中另写一份版本常量。
2. 新建 `.github/release-<version>.md`，更新 README、文档首页和必要的公告。公告使用 `docs/static/announcement.json`，包含唯一标识、内容、有效期和可选链接。
3. 生成预览资源，完成相关测试、静态检查和文档构建，确认子模块提交可在远端获取。
4. 提交并推送代码，创建与 pubspec 一致的标签，例如 `V1.1.0`。
5. Release workflow 构建 Windows、macOS、Linux。三平台均成功后才发布 GitHub Release，上传工件和 `SHA256SUMS.txt`。
6. 检查 Release 实际附件、版本和校验和，确认 Pages 部署成功。

带 `-alpha`、`-beta`、`-rc` 等后缀的版本会标记为预发布；无后缀版本为正式发布。仅推送标签或看到 workflow 开始，不能视为安装包已发布成功。
