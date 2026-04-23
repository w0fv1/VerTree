---
sidebar_position: 5
---

# 使用指南

## 推荐工作流

### 1. 先选一个需要长期维护的文件

比如设计稿、文档、配置文件、脚本。Vertree 更适合“单文件持续演进”的场景。

### 2. 建立第一个阶段版本

对当前文件执行一次“备份”或“快速备份”，生成第一个版本节点。

- 需要备注时用“备份”
- 只想快速留档时用“快速备份”

### 3. 对高频修改文件开启监控

监控后，Vertree 会在原文件同目录创建 `*_bak` 文件夹，并按设置中的频率自动写入备份副本。

你可以在设置页调整：

- `monitorRate`
- `monitorMaxSize`

### 4. 需要回退时，从旧版本再开新分支

不要直接在旧版本文件上覆盖修改。更合适的方式是：

1. 打开旧版本
2. 从该版本再执行一次备份
3. 让 Vertree 自动生成分支版本

这样版本树会保持清晰。

## 从哪里触发操作

### Windows

- 文件右键菜单
- 托盘菜单
- 应用主界面
- 监控页 / 版本树页 / 设置页

### macOS

- Finder Services
- 应用菜单
- 菜单栏图标
- 应用主界面

### Linux GNOME

- GNOME Files 右键菜单
- 托盘菜单
- 应用主界面
- 设置页

### 命令行

- `vertree /path/to/file`
- `vertree backup /path/to/file`
- `vertree monit /path/to/file`
- `vertree express-backup /path/to/file`

## 监控页能做什么

- 手动添加监控任务
- 暂停 / 恢复任务
- 删除任务
- 打开备份目录
- 清理任务对应的备份文件
- 清理无效任务

![monitor-tasks-page](/img/usage/monitor-tasks-page.png)

## 设置页能做什么

- 切换语言
- 切换主题模式
- 调整监控频率与最大备份数
- 开关 Windows / Linux GNOME 菜单集成
- 开关开机自启
- 打开配置文件和日志目录
- 打开官网、GitHub 与捐助页面
- 查看本机 HTTP API 地址和 OpenAPI 文档
- 检查版本更新

![settings-page](/img/usage/settings-page.png)

文档里的常规界面截图默认使用浅色主题；只有在专门说明暗色模式时，才会切换到深色截图。

## 版本树页能做什么

- 查看主线与分支结构
- 聚焦当前版本所在节点
- 快速理解最新版本、分支数和节点数
- 从版本树继续回看和整理单文件演进过程
- 右键任意版本节点，直接生成“分享到局域网”的二维码和分享链接

![version-tree-page](/img/usage/version-tree-page.png)

## 局域网分享怎么用

1. 在版本树页右键目标版本节点
2. 选择“分享到局域网”
3. 把弹窗里的短分享链接或二维码发给同一局域网内的接收方
4. 接收方用浏览器打开 `https://vertree.w0fv1.dev/f#...`
5. 页面会优先自动探测可达的局域网地址，成功后直接开始下载

补充说明：

- 分享链接里不会暴露本地绝对路径，只包含一个 Base62 分享键和压缩后的 RFC1918 候选局域网地址
- 这是局域网直连能力，不会把文件上传到公网服务器
- 建议接收方使用较新的 Chrome、Edge、Firefox 或 Safari 打开分享页
- 如果浏览器因为 HTTPS / 本地网络策略无法自动选路，分享页也会展示可手动点击的候选直连地址
- 默认分享格式是更短的 `/f#<payload>`

## 本机 HTTP API 能做什么

如果你要做自动化验证或本地集成，可以通过设置页打开 API 文档，也可以直接访问：

- `GET /api/v1/health`
- `POST /api/v1/app/quit`
- `POST /api/v1/ui/navigation`
- `POST /api/v1/ui/window-state`
- `POST /api/v1/ui/theme-mode`
- `POST /api/v1/ui/file-tree/viewport`
- `POST /api/v1/ui/screenshot`
- `GET/POST/PATCH/DELETE /api/v1/monitor-tasks`
- `GET /api/v1/monitor-tasks/{id}/backups`
- `POST /api/v1/monitor-tasks/{id}/verification-writes`
- `POST /api/v1/backups`
- `GET /api/v1/backups`
- `GET /api/v1/version-files`
- `GET /api/v1/version-trees`
- `GET /api/v1/file-shares`
- `POST /api/v1/file-shares`
- `GET /api/v1/file-shares/{token}`
- `DELETE /api/v1/file-shares/{token}`

默认只监听 `127.0.0.1`，不会暴露到局域网。

如果你要刷新文档图片，可以在开发机上直接运行：

```bash
python tools/update_doc_images.py
```

脚本会自动确保应用已启动，跳转页面并导出 PNG。

如果你需要控制 `flutter run` 进程本身，而不只是调用应用内 API，可以再配合仓库根目录的 `dev_server.py` 使用，它提供 `reload`、`hot-restart`、`restart-process` 等本地控制端点。

## 使用建议

- 旧版本只读，新增修改尽量通过“备份/分支”继续
- 监控适合高频保存文件，不适合超大目录型项目
- 发布前或重要节点前，建议手动做一次带备注备份
- 如果系统托盘不可用，优先从主窗口和设置页确认平台集成状态
