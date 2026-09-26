---
title: 右键菜单与命令行
description: 配置 Windows 两套菜单，区分单文件命令与Windows 多选文件工具。
sidebar_position: 7
---

# 右键菜单与命令行


文件相关动作尽量从文件本身开始。Windows 有两套菜单；macOS 与 Linux 使用各自的系统集成，不保证所有平台菜单完全相同。

## Windows 右键菜单

在“设置 → 系统集成”中分别管理：

| 菜单 | 位置 | 3.0.0 的设置 |
| --- | --- | --- |
| Windows 11 新菜单 | 右键后的 `Vertree` 子菜单 | 总开关与 8 个单项开关 |
| 经典菜单 | Windows 10 右键；Win11 的“显示更多选项” | 单项开关，可收起到 Vertree 子菜单 |

两组使用相同的“图标、说明、右侧滑动开关”形式，点击整行也可切换。**只是样式统一，选择状态仍彼此独立。** 切换经典菜单布局不会重置单项选择。

:::info 版本差异
从 **3.0.0** 开始，两套菜单均支持逐项设置，Windows 文件工具支持文件和目录多选。2.0.1 及更早版本可能没有这些入口，请先核对安装版本。
:::

## 每一项做什么

| 菜单项 | 行为 | 目标范围 |
| --- | --- | --- |
| 预览文件 | 打开只读内容预览 | 单个文件 |
| 备份文件 | 创建可填写备注的版本副本 | 单个文件 |
| 快速备份 | 直接创建版本副本 | 单个文件 |
| 监控文件变动 | 添加监控任务 | 单个文件 |
| 局域网分享下载 | 创建临时分享 | 单个文件 |
| 查看文件版本树 | 读取同目录版本关系 | 单个文件 |
| 查看／解除文件占用 | 打开独立占用页面 | 文件、目录、多选；Windows 3.0.0 |
| 快速删除（永久） | 打开删除页面并要求确认 | 文件、目录、多选；Windows 3.0.0 |

删除和解除占用没有首页或标题栏快捷按钮入口。右键带入所选目标后，需要补充选择时直接点击页面里的目标卡片，不需要手动输入路径。

## 升级后的菜单

3.0.0只从 `settings.json` 读取偏好，不再从历史配置或注册表猜测并导入菜单选择。Windows 11 包身份由安装过程注册；应用的显示开关不等同于卸载安装包。

移动过便携目录或保留多个安装位置时，从准备保留的版本重新应用菜单。缺失、重复或图标陈旧时见[排障指南](troubleshooting.md)。不要自行清理无关注册表项目。

## macOS 和 Linux

Finder Services 提供备份、快速备份、监控和版本树入口。GNOME Files 提供备份、快速备份、监控、局域网分享和版本树，依赖 Nautilus Python 扩展。预览可从版本树或 CLI 打开。详情见 [macOS](../macos.md)、[Linux](../linux.md)。

## 命令行

未加入 PATH 时使用可执行文件完整路径。含空格路径加引号；PowerShell 调用带空格的可执行路径时使用 `&`。

```powershell
& 'C:\Program Files\Vertree\vertree.exe' preview 'D:\项目\方案.docx'
& 'C:\Program Files\Vertree\vertree.exe' backup 'D:\项目\方案.docx'
```

| 动作 | 作用 |
| --- | --- |
| `vertree "文件路径"` / `viewtree` | 查看版本树 |
| `vertree preview "文件路径"` | 只读预览 |
| `vertree backup "文件路径"` | 普通备份 |
| `vertree express-backup "文件路径"` | 快速备份 |
| `vertree monit "文件路径"` | 监控，也接受 `monitor` |
| `vertree share "文件路径"` | 局域网分享 |

以上动作每次接收一个文件。**只有 Windows 文件工具**支持多选文件或目录：

```powershell
& 'C:\Program Files\Vertree\vertree.exe' unlock 'D:\测试目录'
& 'C:\Program Files\Vertree\vertree.exe' fast-delete 'D:\待删除测试目录' 'D:\待删除测试文件.bin'
```

`fast-delete` 仍会打开确认界面，不是免确认的命令行递归删除。`--selection-file` 是 Explorer 内部传递多选目标的协议，不是授权绕过。需要结构化响应的已公开业务接口见[本机 API](../tutorial-develop/local-api.md)。
