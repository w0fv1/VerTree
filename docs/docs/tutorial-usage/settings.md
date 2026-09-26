---
title: 设置与配置文件
description: 了解主题、监控、菜单设置，以及唯一 settings.json 的结构和读写规则。
sidebar_position: 8
---

# 设置与配置文件


首页点击“设置”，调整外观、系统集成、监控和本机 API。一般使用通过界面修改即可，不必编辑 JSON。

## 常用设置

| 区域 | 可以调整什么 |
| --- | --- |
| 界面与外观 | 简体中文、English、日本語；浅色、深色、跟随系统 |
| 系统集成 | 平台菜单、自启动、托盘行为 |
| 监控文件设置 | 最小备份间隔和每任务的快照数量上限 |
| 本机 HTTP API | 默认关闭；启用后查看实际地址与本次进程的 Token |
| 资源与文件 | 配置文件、日志、版本与项目链接 |

Windows 3.0.0中的新旧菜单单项形式统一，但不强制同步选中状态。删除与解除占用只从文件右键菜单进入，不在首页增加入口。

## 只有一份应用配置

Windows 的默认位置：

```text
%APPDATA%\dev.w0fv1\vertree\settings.json
```

其他平台从设置中的“打开 settings.json”取得实际路径。主程序写入这份文件，Windows 菜单扩展只读相关字段。

3.0.0不读取旧 `config.json`，不生成或恢复 `.previous`；初始化时清理这两个固定的旧文件名。写入过程短暂使用 `.tmp`，完成后替换正式文件，它不是另一份配置，也不会在启动时导入。

配置损坏或 schema 不受支持时，记录错误并使用默认值，下一次显式写入替换原文件。没有历史配置恢复保证。需要手工编辑时先退出应用，避免运行中的内存状态覆盖修改。

## 当前数据结构

配置是 `_schemaVersion: 1` 的扁平 JSON。下面是**示例子集**，不是启动必须写满的模板，也不含个人任务或真实路径：

```json
{
  "_schemaVersion": 1,
  "locale": "zhCn",
  "themeMode": "system",
  "launch2Tray": false,
  "win11MenuEnabled": true,
  "windows11MenuActions": ["preview", "backup", "monitor", "fileUsage", "fastDelete"],
  "windowsLegacyMenuActions": ["preview", "backup", "viewTree"],
  "legacyMenuCollapsed": false,
  "monitorRate": 5,
  "monitorMaxSize": 50,
  "monitorTasks": [],
  "localHttpApiEnabled": false,
  "lastBrandSloganIndex": 0
}
```

菜单可选名称为 `preview`、`backup`、`expressBackup`、`monitor`、`share`、`viewTree`、`fileUsage`、`fastDelete`。显式空数组表示不选任何动作；字段缺失不一定等同于空数组，默认行为由当前代码定义。

`monitorTasks` 内使用 `id`、`filePath`、`enabled`，并持久化部分可重新计算的显示信息，如 `backupDirPath`、`fileExists`。归档任务可能有 `removed: true`，不要手工伪造 UUID 或把备份目录改到不属于该任务的位置。

`lastBrandSloganIndex` 为 0–9，记录上次启动文案，帮助下一次避开重复。随机文案在一次运行期间保持稳定。应用还可能保存公告确认、初始化标记与窗口状态，这些不是需要用户设置的功能参数。

快照清单、文件操作报告和日志是业务数据，不是多份应用配置。API Token 属于运行凭据，不要写进文档或公开反馈。

## 哪些改动不会做

调整文案和首页样式不会重置监控任务；菜单样式统一不会合并两套菜单的选择。清理旧配置也不会顺带删除旧 `*_bak` 内容。需要清理文件时，请单独核对操作范围。
