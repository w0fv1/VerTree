# Office Viewer 集成

版本树节点的打开对话框和右键菜单提供「预览」。Windows 使用 WebView2，macOS 使用 WKWebView 在 Vertree 内显示；Linux 使用本机浏览器，关闭 Vertree 的预览对话框后该页面的文件访问立即失效。

应用内同时只保留一个预览窗口。`PreviewDialogController` 统一管理所有入口的预览路由：新请求先移除旧预览，等待其退出浮层并销毁页面后再打开；连续请求只显示最后一个文件，不关闭其他类型的对话框。旧预览沿用页面销毁时的 session 清理流程。

Windows 资源管理器也提供「预览文件」：Win11 新菜单在 `Vertree` 子菜单内；传统菜单按设置显示在顶层或 `Vertree` 子菜单内。点击后启动/唤起 Vertree，直接打开所选文件的预览，无需先建立版本树或监控文件。命令行为 `vertree.exe preview "文件路径"`。

传统菜单的注册、单项开关、布局切换和语言更新统一使用 `WindowsMenuAction` / `WindowsMenuPlan`。菜单写入当前用户的 `Software\Classes\*\shell`；切换布局保留已选项目，先写新布局再删除旧布局。升级时从旧注册表迁移选择，原来启用了传统菜单的用户自动获得预览项；原来关闭全部菜单的用户保持关闭。设置页可以单独切换预览项，折叠时也可调整各项。

Win11 新菜单由安装包维护包身份，应用内开关只修改显示配置，不再卸载包；新菜单固定包含六个动作，传统菜单的单项设置仅影响传统菜单。`refresh_win11_menu.ps1` 默认不重启资源管理器，维护时可显式传入 `-RestartExplorer` / `-KillDllHost`。Inno 安装包卸载会清理当前用户和旧机器级传统菜单，包括折叠根和预览项。

## 构建

需要 Flutter、Python 3、Node.js 22.12+（推荐 24）。Windows 还需要 PATH 中可用的 NuGet CLI，运行设备需要 Microsoft Edge WebView2 Runtime。

```sh
git submodule update --init vendor/office-viewer
python tools/build_office_preview.py
flutter pub get
flutter run -d windows
```

macOS / Linux 替换最后一行的设备名称。前端改动后重新运行构建脚本，再 hot restart；首次添加 WebView 插件需要完整重启应用。已有 node_modules 时可加 `--skip-install`。三平台 release 工作流会自动生成预览资源。

## 结构

- `vendor/office-viewer`：上游 `https://github.com/w0fv1/Office-Viewer` 的固定 Git submodule 提交，预览能力在该仓库维护，Vertree 直接复用。无需初始化上游的 vscode-office 子模块，它是能力参考，不参与此预览构建。
- `web/office_preview`：只读 React 入口，直接复用上游 `registry`、`Preview`、解析器和样式。依赖通过该目录的 package-lock.json 固定，升级上游时同步检查其 package.json 中的运行时依赖。
- `assets/office_viewer`：Vite 生成的离线资源，作为 Flutter assets 打包，生成内容不入 Git。
- `FilePreviewSession`：每次预览建立临时磁盘快照，不设固定文件大小上限；关闭后删除快照。监听随机 loopback 端口，只服务当前随机 token 下的文件和内置资源，支持 HTTP Range 分段读取。校验 Host / Origin，不提供目录遍历、写文件或跨域接口。CSP 禁止外部网络资源。
- `FilePreviewDialog`：管理 WebView 和 session 的生命周期，关闭后销毁视图和服务；Windows 的浏览器环境在应用内共享，由 Flutter 引擎退出时回收，避免反复创建浏览器环境。WebView 数据目录放在用户应用支持目录，以支持安装在只读目录下的应用。

预览不依赖本机自动化 API 或局域网分享服务开关，不向云端上传文件，不提供编辑或保存功能。

注册器通过可选的 `loadUrl` 能力声明按 URL 加载。音视频、普通图片、字体和 PDF 复用本地文件 URL，不再先把整个文件读进 Flutter 和 JavaScript 内存；PDF 文本提取使用 pdf.js 的分段请求。Office、压缩包、文本等解析器仍读取完整内容，实际可打开的大小取决于解析器和可用内存。磁盘快照需要与原文件大小相当的临时空间，开始预览前有一次复制开销。

## 格式边界

以固定版本的上游 registry 为准。支持 DOCX / DOTX / ODT / RTF，XLSX / XLSM / XLS / ODS / CSV / TSV，PPTX / PPTM，PDF，Markdown、HTML、SVG、图片、结构化文本、代码和多种压缩文件。

这是上游现有能力的嵌入，不保证 Office 原版版式：PPTX 显示幻灯片画面和备注；旧 XLS 的支持有限；XMind 显示主题层级导图，PSD 显示合成图及图层名称；7Z 展示条目列表；未知格式先按内容检测 UTF-8 / 带 BOM 的 UTF-16 文本，识别成功直接显示正文，否则仅显示「不支持预览此文件」。旧 DOC / PPT 没有专用渲染器。损坏或加密文件可能解析失败，仍可通过系统程序打开。

外部图片、字体和链接不联网加载。WebView 自身的 PDF 显示能力因平台而异，PDF 文本提取由上游 pdf.js 提供。

## 验证

```sh
npm --prefix web/office_preview test
flutter test test/service/file_preview_session_test.dart
flutter analyze
```

Windows 菜单回归测试：`flutter test test/platform/windows_menu_model_test.dart test/component/app_command_handler_test.dart`。原生 COM 菜单及 Windows 命令行参数验证（无需注册菜单）：

```sh
cmake -S windows/context_menu/tests -B build/context-menu-tests -A x64
cmake --build build/context-menu-tests --config Release
ctest --test-dir build/context-menu-tests -C Release --output-on-failure
```

前端测试使用子模块自带真实样例，验证注册器到解析结果；Dart 测试验证快照、特殊字符文件名、超过 64 MiB 的文件、分段请求、资源 MIME、访问边界及关闭回收。Windows / macOS 的原生 WebView 仍需在对应平台做 UI 验证。

本次集成在 Windows 已通过主程序 Debug / Release 构建、64 项 Flutter 测试、16 项嵌入前端测试和静态分析；独立原生测试窗口中验证了 DOCX 正文与大纲、XLSX 多 Sheet 切换、PDF 页面与文本、Markdown、7Z 条目，以及关闭后再次打开。菜单重构另通过原生 COM 枚举、六项菜单及特殊字符路径传参验证；新安装包尚未覆盖安装后在 Explorer 中点击验收。macOS / Linux 尚未进行实机验证。

## 本轮预览改进

- 删除十六进制、文本尝试说明和预览页中的 `Fallback · 只读 · Office Viewer` 标注。
- 新增 DOCM / DOTM、XLTX / XLTM、PPSX / PPSM / POTX / POTM、OTT / OTS / ODP / OTP、FODT / FODS / FODP；模板复用已有解析器，OpenDocument 共用命名空间感知的 XML 解析入口。演示文稿展示逐页文本与备注。
- 新增 MP3 / WAV / OGG / OGA / OPUS / FLAC / M4A / AAC 和 MP4 / M4V / WEBM / OGV / MOV，使用原生音视频控件；CSP 允许本地会话和 blob 媒体，解码失败显示不支持。
- 新增 EML 邮件、FB2 电子书、CBZ 漫画、AVIF / APNG / SVGZ 图片；EPUB 从章节清单升级为按章节阅读正文与内嵌图片。
- 邮件显示解码后的主题、收发件人、正文及附件名称；附件尚不能在邮件预览中打开。电子书和邮件不联网加载外部资源。

仍不支持旧 DOC / PPT、MSG、MOBI / AZW 和加密电子书的专用预览。音视频能否播放取决于文件实际编码及 WebView 所在系统，不保证每一种编码组合。

本轮 Office Viewer 已通过 75 项测试、lint 和生产前端构建。嵌入页面在 Windows Chrome 中检查了未知中文文本、未知二进制、邮件正文、FB2 章节切换、WAV 时长和 MP4 画面与播放。新增格式尚未逐个在 macOS / Linux 原生 WebView 实机验收。

## 取消固定大小限制

2026-09-07 移除 64 MiB 门槛，并改为磁盘快照、HTTP Range 和注册器 URL 加载能力。通过 68 项 Flutter 测试、81 项 Office Viewer 测试、19 项嵌入页面测试及静态检查；80 MiB 实体文件测试覆盖末尾分段读取，并验证并发、越界请求、HEAD、空文件和关闭操作。前端测试验证大视频不调用整文件 fetch。两个前端生产构建通过。

本轮实际浏览器访问临时预览地址被 Chrome 以 `ERR_BLOCKED_BY_CLIENT` 阻止，因此没有把大视频播放或 PDF 实机显示记为通过。各平台原生 WebView 仍需验收。最新上游缺口详见 [上游能力核对](office-preview-upstream-audit.md)。

## 上游格式与画面补齐

2026-09-07 后续增加 HEIC / HEIF、Parquet、CRX2 / CRX3、CUR、PJP / PJPEG 和 Java `.class`，并将 PPTX 升级为幻灯片画面、PSD 升级为合成图、XMind 升级为可缩放的主题层级导图。所有解析、渲染、Worker 和格式注册均在 Office-Viewer 实现；Vertree 同步依赖并直接复用，不增加另一套解析器或 Java 原生桥接。

Parquet 每页显示 100 行，通过现有 `loadUrl` 能力发起 HTTP Range 请求。Java 在本地 Worker 中反编译，不要求安装 Java，不执行 class；关闭预览或超过 30 秒时终止。PPTX 不执行宏或动画；OpenDocument 演示文稿仍显示文本。PSD 需要文件包含合成图。XMind 的原始样式、图片、附件和关系线尚未完整复现。

Office-Viewer 100 项测试和嵌入页面 20 项测试通过。使用无扩展的 Chrome 经实际 `FilePreviewSession` 地址验证了 PPTX 文字、表格、图表和翻页，Parquet 205 行分页与 206 请求，HEIC 1280×854 照片、32×32 CUR、640×400 PSD、XMind 和 Java 方法源码；同时回归了 80 MiB 视频地址和 PDF 文本加载。此前 Chrome 扩展环境的地址阻断未在此测试环境复现。macOS / Linux 及原生 WebView 的完整 UI 验收仍未覆盖。

最终通过 68 项 Flutter 测试与 `flutter analyze`，Office-Viewer 的 `tauri build --debug --no-bundle` 和 Vertree Windows Release 构建成功。安装包：`build/dist/vertree-windows-x64-1.0.0-visual-formats-20260907-setup.exe`。
