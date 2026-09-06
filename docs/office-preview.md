# Office Viewer 集成

Vertree 直接复用 Office-Viewer 的 React 预览模块，生成离线资源后嵌入 Flutter。Windows 使用 WebView2，macOS 使用 WKWebView，Linux 使用本机浏览器；不在 Flutter 中启动 Tauri。

集成说明已整理进文档站，避免在此维护另一套格式列表和过时的逐轮开发记录：

- [文件预览与格式支持](docs/tutorial-usage/preview.md)：入口、完整格式表、未知格式与大文件边界。
- [右键菜单与命令行](docs/tutorial-usage/entry-points.md)：Windows 两套菜单、迁移与 CLI。
- [预览架构](docs/tutorial-develop/preview-architecture.md)：会话、路由、加载方式与两个仓库的职责。
- [开发与构建](docs/tutorial-develop/develop.md)：首次构建、子模块更新、测试和发布。
- [上游能力核对](office-preview-upstream-audit.md)：固定参考版本的支持缺口与实现记录。

## 快速构建

需要 Flutter、Python 3、Node.js 24；Windows 还需要 NuGet CLI 和 WebView2 Runtime。

```bash
git submodule update --init vendor/office-viewer
python tools/build_office_preview.py
flutter pub get
flutter run -d windows
```

macOS / Linux 替换设备名即可。首次构建必须生成预览资源；前端改动后可运行 `python tools/build_office_preview.py --skip-install`，再 hot restart。原生插件或启动层改动需要完整重启。

预览能力在 [Office-Viewer](https://github.com/w0fv1/Office-Viewer) 维护，Vertree 固定使用子模块提交。先推送 Office-Viewer，再推送 Vertree 指针，保证 CI 可以获取源码。
