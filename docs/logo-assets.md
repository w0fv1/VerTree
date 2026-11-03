# Logo 资源

唯一品牌源文件是 [`assets/img/logo/logo.png`](../assets/img/logo/logo.png)。界面、Linux、非 Windows 托盘和官网直接复用它；Windows ICO、包图标和 macOS AppIcon 由 [`tools/sync_logo_assets.py`](../tools/sync_logo_assets.py) 生成，不单独编辑。

修改源图后，在仓库根目录执行并提交生成文件：

```bash
python -m pip install Pillow
python tools/sync_logo_assets.py
```

普通克隆与构建直接使用已提交的资源，无须安装 Pillow。现有源图是 256 × 256；更大尺寸不会增加原图细节，高清源图仍替换同一文件。

## Windows

- 系统主题、窗口图标和 DPI 生命周期：[`ShellIcons`](../windows/runner/shell_icons.cpp)。
- 托盘主题通知：[`WindowsShellIcon`](../lib/platform/windows_shell_icon.dart) 与 [`TrayManager`](../lib/component/tray_manager.dart)。
- EXE 与安装器快捷方式使用生成的通用 `logo.ico`；运行窗口的任务栏图标元数据由 `ShellIcons` 指向当前主题的内嵌资源。任务栏身份关联见 [`win32_window.cpp`](../windows/runner/win32_window.cpp)。
- 包资源的尺寸与深浅色变体见生成脚本；[`build_icon_resources.ps1`](../windows/build_icon_resources.ps1) 将它们编入 `resources.pri`。打包脚本自动执行，手动运行 Inno Setup 前需先执行。
- 回归验证：[`资源生成测试`](../tools/tests/test_logo_assets.py)、[`原生主题与 DPI 测试`](../windows/runner/tests/shell_icons_test.cpp)、[`Flutter 通道测试`](../test/platform/windows_shell_icon_test.dart)。

## 官网与动作图标

官网通过 Docusaurus `staticDirectories` 读取公共目录，`docs/build/logo.png` 和 `logo.ico` 是网站构建产物。首页使用带替代文字的真实示例截图。

预览动作图标与品牌 Logo 分开，位于 `assets/img/icon/preview.*`，由 [`tools/build_preview_icon.py`](../tools/build_preview_icon.py) 生成，许可见同目录 `LICENSE-fluent-icons.txt`。

界面动作图标的主题适配统一由 [`themed_assets.dart`](../lib/component/themed_assets.dart) 管理；分享图标回归见 [`share_action_icon_test.dart`](../test/component/share_action_icon_test.dart)。
