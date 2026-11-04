# Logo 资源

唯一品牌源文件是 [`assets/img/logo/logo.svg`](../assets/img/logo/logo.svg)。界面 PNG、Windows ICO、包图标和 macOS AppIcon 由 [`tools/sync_logo_assets.py`](../tools/sync_logo_assets.py) 生成，不单独编辑。

修改源图后，在仓库根目录执行并提交生成文件：

```bash
python -m pip install Pillow resvg-py==0.5.0
python tools/sync_logo_assets.py
```

普通克隆与构建直接使用已提交的资源，无须安装生成依赖。所有尺寸从 SVG 渲染，浅色图案仅反转 RGB，透明度与轮廓保持一致。

## Windows

- 系统主题、窗口图标和 DPI 生命周期：[`ShellIcons`](../windows/runner/shell_icons.cpp)。
- 托盘主题通知：[`WindowsShellIcon`](../lib/platform/windows_shell_icon.dart) 与 [`TrayManager`](../lib/component/tray_manager.dart)。
- 当前用户的启动快捷方式、固定副本与通知身份：[`ShellShortcuts`](../windows/runner/shell_shortcuts.cpp)。回归验证：[`真实快捷方式测试`](../windows/runner/tests/shell_shortcuts_test.cpp)。
- EXE 内嵌资源由 `logo.ico` 和主题变体生成；窗口与快捷方式的主题选择见 [`ShellIcons`](../windows/runner/shell_icons.cpp) 和 [`ShellShortcuts`](../windows/runner/shell_shortcuts.cpp)，安装位置见 [`setup.iss`](../windows/setup.iss)。任务栏身份关联见 [`win32_window.cpp`](../windows/runner/win32_window.cpp)。
- 包资源的尺寸与深浅色变体见生成脚本；[`build_icon_resources.ps1`](../windows/build_icon_resources.ps1) 将它们编入 `resources.pri`。打包脚本自动执行，手动运行 Inno Setup 前需先执行。
- 回归验证：[`资源生成测试`](../tools/tests/test_logo_assets.py)、[`原生主题与 DPI 测试`](../windows/runner/tests/shell_icons_test.cpp)、[`Flutter 通道测试`](../test/platform/windows_shell_icon_test.dart)。

## 官网与动作图标

官网通过 Docusaurus `staticDirectories` 读取公共目录，`docs/build/logo.png` 和 `logo.ico` 是网站构建产物。首页使用带替代文字的真实示例截图。

动作图标的唯一映射是 [`actions.json`](../assets/img/icon/actions.json)，选用 Flutter Material 图标库。运行 `python tools/build_action_icons.py --flutter-sdk <Flutter SDK 路径>`，生成界面图标定义、原生菜单资源和托盘所需图片。许可见 `assets/img/icon/LICENSE-material-icons.txt`。生成文件不单独编辑。

- 界面定义：[`action_icons.dart`](../lib/component/action_icons.dart)。
- Explorer 主题选择：[`vertree_context_menu.cpp`](../windows/context_menu/vertree_context_menu.cpp)。
- 资源验证：[`test_action_icons.py`](../tools/tests/test_action_icons.py)。
- Windows 验收使用 EXE 安装包，要求见 [`Agents.custome.md`](../Agents.custome.md)。
