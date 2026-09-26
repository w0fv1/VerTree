---
title: Linux 使用说明
description: 选择 Linux 安装包，检查 GNOME Files、托盘和本机浏览器的依赖与边界。
sidebar_position: 21
---

# Linux 使用说明


Linux 提供版本树、手动备份、监控和本机浏览器预览，桌面集成以 GNOME 为主要目标。Windows 的快速删除与解除占用不属于 Linux 当前能力。

## 安装包与桌面依赖

从[下载页](/download)选择 x64 DEB、RPM 或 TAR.GZ。便携包整体解压，不要丢掉随包资源。普通运行不需要安装 Node.js、Python 或 Flutter 开发工具。

| 集成 | 需要什么 |
| --- | --- |
| GNOME Files 右键菜单 | Debian / Ubuntu 的 `python3-nautilus`，或 Fedora 的 `nautilus-python` |
| GNOME 托盘 | 当前会话可用的 AppIndicator 扩展与相应运行库 |
| 交互预览 | 可打开本机地址的浏览器 |
| 后台预览图 API | PATH 中的 Chromium / Google Chrome |

缺少托盘支持时应用可回退显示主窗口，不应表现为找不到窗口却强制常驻。设置中的环境提示用于检查依赖和是否已启用。

## 文件菜单与预览

GNOME Files 扩展提供备份、快速备份、监控、局域网分享和版本树入口。安装扩展后可能需要按设置提示重新打开 Files。它不与 Windows 两套菜单共享所有配置。

文件预览从版本树或 `vertree preview "文件路径"` 打开本机浏览器。保持 Vertree 预览对话框打开；关闭或切换会话后旧地址失效，浏览器标签页可能仍保留已显示画面。

## 从源码运行

需要 Flutter stable（Dart 满足项目约束）、Python 3、Node.js 24，以及 Clang、CMake、Ninja、pkg-config、GTK3、通知与托盘开发库。CI 的具体依赖见仓库 `.github/workflows/release.yml`。

```bash
flutter config --enable-linux-desktop
python tools/build_office_preview.py
flutter pub get
flutter run -d linux
```

网络请求失败时先定位包下载、代理还是 DNS，不要把全局关闭代理当作固定安装步骤。只为当前命令调整必要环境。

## 打包与验证

```bash
linux/build_linux_release.sh
SKIP_FLUTTER_BUILD=1 linux/build_linux_deb.sh
SKIP_FLUTTER_BUILD=1 linux/build_linux_rpm.sh
```

产物按 `pubspec.yaml` 的版本命名。源码与工具链流程见[开发与构建](tutorial-develop/develop.md)，菜单不显示见[排障指南](tutorial-usage/troubleshooting.md)。

这轮文档与视觉审计在 Windows 上执行，不替代 GNOME、其他桌面环境或 Linux 文件系统的实机验收。
