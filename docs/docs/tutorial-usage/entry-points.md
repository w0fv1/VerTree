---
sidebar_position: 4
---

# 右键菜单与命令行

## Windows 右键菜单

Windows 有两套菜单，设置分别生效：

| 菜单 | 位置 | 可调整内容 |
| --- | --- | --- |
| 传统菜单 | Windows 10 文件右键菜单；Windows 11 的“显示更多选项” | 逐项启用预览、备份、快速备份、监控、分享、版本树；可折叠到 `Vertree` 子菜单 |
| Windows 11 新菜单 | 文件右键后的 `Vertree` 子菜单 | 整体显示开关；固定提供六个动作，不跟随传统菜单的逐项选择 |

在 Vertree 设置页打开右键菜单相关设置，选择所需项目。传统菜单切换折叠布局时会保留已选项目，折叠状态下仍可逐项调整。

选择“预览文件”会唤起 Vertree 并直接显示所选文件，不要求该文件已有版本号。应用已运行时，命令交给现有实例处理。

### 升级后的菜单

1.1.0 统一了传统菜单注册逻辑，并迁移旧菜单选择。此前启用了传统菜单的用户会自动获得预览项；此前关闭全部传统菜单的用户保持关闭。

Win11 新菜单的包身份由安装包维护，应用内关闭新菜单只是隐藏入口。修改传统菜单单项设置不会同时修改新菜单。

菜单缺失、重复或仍指向旧目录时，先检查是否留有多个安装目录，再从当前使用的 Vertree 设置页重新应用菜单配置。更多排查见[常见问题](troubleshooting.md)。

## macOS 和 Linux

macOS Finder Services 和 Linux GNOME Files 当前提供备份、快速备份、监控、查看版本树。它们没有与 Windows 完全相同的菜单配置；文件预览可从版本树内或命令行打开。

托盘、菜单栏和应用菜单提供常用页面与操作入口。具体依赖见 [macOS](../macos.md)和 [Linux](../linux.md)。

## 命令行

以下命令中的 `vertree` 表示应用可执行文件。如果没有加入 PATH，请替换为完整路径。Windows PowerShell 执行当前目录的程序时写作 `.\vertree.exe`。

| 命令 | 作用 |
| --- | --- |
| `vertree "文件路径"` | 查看文件版本树 |
| `vertree viewtree "文件路径"` | 显式查看版本树；也接受 `tree` / `open` |
| `vertree preview "文件路径"` | 打开只读预览 |
| `vertree backup "文件路径"` | 打开备份流程 |
| `vertree express-backup "文件路径"` | 快速备份 |
| `vertree monit "文件路径"` | 添加监控；也接受 `monitor` |
| `vertree share "文件路径"` | 打开局域网分享流程 |

例如：

```powershell
.\vertree.exe preview "D:\项目文件\设计稿.psd"
.\vertree.exe backup "D:\项目文件\方案.docx"
.\vertree.exe "D:\项目文件\方案.0.1.docx"
```

每次命令接收一个文件路径。含空格的路径必须加引号；目录预览和批量多文件参数不是当前 CLI 的使用方式。

命令可能打开桌面窗口或对话框。需要结构化响应、自动化查询和错误信息时，使用[本机 HTTP API](../tutorial-develop/local-api.md)。
