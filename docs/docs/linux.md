---
sidebar_position: 8
---

# Linux 说明

## 当前状态

Vertree 已进入 Linux 桌面发布链路，当前仓库会构建：

- `vertree-linux-x64-<version>.tar.gz`
- `vertree-linux-x64-<version>.deb`
- `vertree-linux-x64-<version>.rpm`

Linux 侧当前最完整的集成目标是 GNOME，会提供：

- 托盘菜单
- GNOME Files 顶层右键菜单
- 设置页中的集成状态检测与开关
- 开机自启
- 本机 HTTP API 与 OpenAPI 文档

## 开发环境要求

### Flutter / Dart

- Flutter stable
- Dart 3.10.0 或更新版本

项目当前的 SDK 约束见 [pubspec.yaml](../../pubspec.yaml)：

```yaml
environment:
  sdk: '>=3.10.0 <4.0.0'
```

### 常见系统依赖

GitHub Actions 的 Linux workflow 当前会安装这些依赖：

- `clang`
- `cmake`
- `ninja-build`
- `pkg-config`
- `libgtk-3-dev`
- `libnotify-dev`
- `libayatana-appindicator3-dev`
- `libblkid-dev`
- `liblzma-dev`
- `rpm`
- `desktop-file-utils`
- `appstream`

如果你要在 GNOME Files 里启用 Vertree 的文件右键菜单，还需要：

- Debian/Ubuntu: `python3-nautilus`
- Fedora: `nautilus-python`

如果你要在 GNOME 里稳定使用托盘，还可能需要系统托盘扩展，例如 AppIndicator 扩展。

## 运行方式

源码构建还需要 Python 3、Node.js 24，并先生成随包携带的 Office Viewer 资源。使用已下载的安装包时不需要这些开发工具。

```bash
flutter config --enable-linux-desktop
python tools/build_office_preview.py
flutter pub get
flutter run -d linux
```

## 文件预览

Linux 从应用预览对话框打开本机浏览器。保持对话框打开才能继续读取文件；切换到另一个预览或关闭对话框后，旧地址失效，浏览器标签页可能仍保留已显示的内容。

当前 GNOME Files 菜单提供备份、快速备份、监控和版本树；预览可从版本树或 `vertree preview "文件路径"` 打开。完整格式和限制见[文件预览](tutorial-usage/preview.md)。

如果系统里设置了全局代理，而代理对 Flutter / pub / git 不稳定，建议在无代理环境下运行：

```bash
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
  flutter run -d linux
```

## GNOME 集成说明

### GNOME Files 右键菜单

- 通过本地 `nautilus-python` 扩展脚本接入
- 设置页可以检测依赖状态，并提供安装 / 重启 Files 的提示
- 当前支持：备份、快速备份、监控、查看版本树

### 托盘

- GNOME 默认不一定显示普通托盘图标
- 如果托盘扩展不可用，Vertree 会回退为显示主窗口，而不是强制托盘常驻
- 设置页会给出“已安装但未启用”或“缺少依赖”的具体提示

## 打包命令

构建 Linux 便携包：

```bash
linux/build_linux_release.sh
```

构建 RPM：

```bash
linux/build_linux_rpm.sh
```

构建 DEB：

```bash
linux/build_linux_deb.sh
```

脚本会从 `pubspec.yaml` 读取版本号，并自动生成与 release 版本一致的归档文件名。
