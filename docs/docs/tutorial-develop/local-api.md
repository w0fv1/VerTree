---
sidebar_position: 6
---

# 本机 API 与开发控制器

Vertree 提供两层本地控制：应用 HTTP API 用于查询和执行业务动作，开发控制器用于管理它启动的 `flutter run` 进程。文件预览和局域网分享各有独立服务，不共用 API 的开关。

## 服务地址

| 服务 | 默认地址 / 端口 | 用途 |
| --- | --- | --- |
| 应用本机 API | `http://127.0.0.1:31414/api/v1` | 监控、备份、版本树、界面与分享管理 |
| 开发控制器 | `http://127.0.0.1:32500` | 启动、重载、重启和日志 |
| 局域网文件服务 | 起始端口 `31424` | 临时分享文件给局域网设备 |
| 文件预览 | 随机 loopback 端口 | 当前预览快照与离线资源 |

应用 API 端口占用时会自动递增。优先从设置页或控制器 `GET /status`、`POST /ensure-ready` 的结果发现实际地址。

## 启用与认证

本机 API 默认关闭。在设置页启用后，复制本次启动的 Token。业务请求使用：

```http
Authorization: Bearer <token>
```

API 索引、OpenAPI 文档和最小探活 `/ping` 不需要 Token；`/health` 和业务接口需要认证。服务只监听 loopback，并校验 Host、Origin 和浏览器 Fetch Metadata。

PowerShell 只读查询示例：

```powershell
$apiBase = 'http://127.0.0.1:31414/api/v1'
$apiHeaders = @{ Authorization = "Bearer $env:VERTREE_API_TOKEN" }
Invoke-RestMethod -Uri "$apiBase/health" -Headers $apiHeaders -NoProxy
Invoke-RestMethod -Uri "$apiBase/monitor-tasks" -Headers $apiHeaders -NoProxy
```

这里的 `VERTREE_API_TOKEN` 是自行设置的示例环境变量。不要把真实 Token 写入文档、版本库或问题反馈。重启应用后重新获取认证信息。

## API 文档与主要能力

运行实例提供完整契约：

- `GET /api/v1`：接口索引。
- `GET /api/v1/openapi.json`：OpenAPI 契约。
- `GET /api/v1/docs`：交互式接口文档。

| 资源 | 常用接口 | 用途 |
| --- | --- | --- |
| 状态 | `GET /health`、`GET /ping` | 运行状态与最小探活 |
| 监控 | `GET/POST /monitor-tasks`、`PATCH/DELETE /monitor-tasks/{id}` | 列表、添加、切换与移除任务 |
| 监控备份 | `GET /monitor-tasks/{id}/backups` | 查询任务备份 |
| 手动备份 | `GET/POST /backups` | 查询与创建版本备份 |
| 版本文件与树 | `GET /version-files`、`GET /version-trees` | 检查文件关系 |
| 界面 | `POST /ui/navigation`、`/ui/window-state`、`/ui/theme-mode` | 页面、窗口、主题控制 |
| 画布与截图 | `POST /ui/file-tree/viewport`、`/ui/screenshot` | 适配版本树与导出界面 |
| 分享 | `GET/POST /file-shares`、`GET/DELETE /file-shares/{token}` | 创建、查询、撤销临时分享 |
| 退出 | `POST /app/quit` | 退出应用进程 |

表中路径均相对于 `/api/v1`。请求字段、响应结构和限制以运行实例的 OpenAPI 为准；其中 `verification-writes` 是会修改文件的测试接口，仅对专用样例使用。

## 开发控制器

在仓库根目录执行：

```bash
python dev_server.py --bootstrap --device windows
```

截图或演示时可禁止启动公告：

```bash
python dev_server.py --bootstrap --device windows --app-arg --no-announcement
```

控制器脚本实现位于 `dev_control_server.py`。它只可靠管理自己启动的 Flutter 子进程，不应接管用户在其他终端运行的进程。

| 方法与路径 | 行为 |
| --- | --- |
| `GET /status` | 控制器、子进程与应用 API 状态 |
| `GET /logs` | 最近输出 |
| `POST /start` | 启动开发应用 |
| `POST /ensure-ready` | 确保应用 API 可用并返回就绪信息 |
| `POST /reload` | 普通 Dart/UI hot reload |
| `POST /hot-restart` | Dart 初始化与路由变更后的重启 |
| `POST /restart-process` | 原生层或启动行为变更后的完整重启 |
| `POST /stop` | 停止控制器持有的进程 |

例如：

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:32500/status' -NoProxy
Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:32500/reload' -NoProxy
```

开发工具会为受控进程准备临时 Bearer Token，并保存到 `.dart_tool/vertree_local_api_token` 供仓库内工具读取。该文件不是要提交的配置。

## 分享页联调与截图

```bash
python dev_server.py --bootstrap --device windows --local-docs
```

本地分享页默认使用 `http://127.0.0.1:33030/f`，启动脚本会向应用注入对应地址。联调本机页面与在真实局域网设备下载是两个不同验证场景。

截图使用 `python tools/update_doc_images.py`。它通过 API 调整页面、窗口与主题，再保存 PNG 到文档资源目录。使用 `.sample/file_version_tree` 中的标准样例，并在提交前检查画面、文本截断和是否含个人路径。

## 文件预览图与自动化接口

以下业务接口均需 Bearer Token；路径指运行 Vertree 的电脑上的绝对路径。

| 方法与路径 | 功能 |
| --- | --- |
| `POST /preview-images` | 后台生成 PNG，直接返回 `image/png` 字节 |
| `GET /preview-capabilities?path=...` | 上游格式清单、图片能力；可选路径检测未知格式是否为文本 |
| `POST /previews` | 传 `path` 打开预览，并关闭上一个预览 |
| `GET /previews/current` | 当前预览路径和 loading / ready / unsupported / error 状态 |
| `DELETE /previews/current` | 关闭当前预览 |
| `POST /versions/{id}/restore` | 恢复版本；可选 `targetPath` 另存 |
| `PATCH /versions/{id}` | 传 `label` 改备注，空字符串清除备注 |
| `POST /version-comparisons` | 传 `leftPath`、`rightPath` 比较 SHA-256 和文本差异 |
| `GET /settings`、`PATCH /settings` | 查询、持久化设置 |
| `POST /batch` | 顺序执行一组动作，逐项返回成功或失败 |
| `GET /jobs`、`POST /jobs` | 查询或创建异步任务 |
| `GET /jobs/{id}`、`DELETE /jobs/{id}` | 任务状态、进度、结果或请求取消 |
| `GET /events` | SSE 实时事件 |
| `GET /diagnostics` | 运行信息、预览状态、任务及近期预览/任务错误 |

### 生成预览图

```powershell
$body = @{
  path = 'C:\Documents\report.pdf'
  width = 1200
  height = 1600
  page = 1
} | ConvertTo-Json
Invoke-WebRequest -Method Post -Uri "$apiBase/preview-images" `
  -Headers $apiHeaders -ContentType 'application/json' -Body $body `
  -OutFile './preview.png' -NoProxy
```

成功响应是 PNG 二进制，不是 JSON、Base64 或图片文件路径。失败响应为 JSON，包含 `success: false`、`code`、`message`。生成使用独立文件快照和后台渲染环境，不打开窗口，也不替换当前交互预览。

- `width`、`height`：默认 1200 × 1600，各为 1–4096 的整数，输出固定像素尺寸。
- `page`：从 1 开始；PDF 页、演示文稿页、工作表、电子书章节、XMind 画布；Parquet 每页 100 行。连续文本/Word 等导出首屏，不能按 Word 的打印页码选择。
- `timeSeconds`：视频时间点，默认 0；其他类型仅接受 0。视频编码支持取决于浏览器引擎。
- 图片、PDF、PPT、视频按比例适配画布；连续文档导出给定宽高内的内容。
- 未知格式由 Office-Viewer 检测文本。未知二进制、音频等没有可视内容的文件返回 `UNSUPPORTED`，不会生成十六进制或文件元信息图片。
- 越界页码 `PAGE_OUT_OF_RANGE`（422）；无效参数（400）；不存在文件（404）；正在生成另一张图片 `RENDER_BUSY`（409）；超时 `RENDER_TIMEOUT`（504）。渲染阶段默认 30 秒，加载与环境初始化另计。
- Windows 使用 WebView2，macOS 使用 WKWebView；Linux 需要 PATH 中存在 Chromium / Google Chrome。能力接口的 `backgroundImageAvailable` 反映平台/依赖是否可用，实际文件仍可能解码失败。

格式清单来自 Office-Viewer 的同一份 registry，构建时生成 `capabilities.json`。已声明扩展名返回 `support: declared`，不代表文件内容一定有效；未知扩展名会实际检测并返回 `supported`、`kind`。

### 版本与设置

版本查询返回的 `id` 为规范化绝对路径的 Base64URL 编码。更改备注会重命名文件，因此必须使用响应中的新 `id` 和 `path`。恢复默认写回同目录未带版本号的原文件；覆盖前先保留 `before-restore` 备份，响应包含 `backupPath`。另存目标的父目录须已存在；不允许把源文件恢复到自己。

比较始终返回 SHA-256；两边均不超过 2 MiB、UTF-8 可解码且不含 NUL 时额外返回文本增删差异。其他文件返回哈希比较，不声称能做 Office 布局差异。

设置支持 `monitorRateMinutes`（非负整数）、`monitorMaxBackups`（正整数）、`themeMode`（system/light/dark）、`launchToTray`（布尔）。PATCH 会完整校验参数后应用并保存。

### 批处理、异步任务与事件

```json
{
  "operations": [
    { "action": "backup", "path": "C:\\Documents\\report.docx", "label": "checkpoint" },
    { "action": "compare", "leftPath": "C:\\Documents\\a.txt", "rightPath": "C:\\Documents\\b.txt" }
  ]
}
```

上述 body 发往 `/batch`；增加 `"action": "batch"` 后也可以发往 `/jobs` 后台执行。单个异步任务的 body 为 `action` 加对应参数。支持动作：backup、monitor、share、restore、compare；每批 1–100 项，失败不会回滚先前完成项。share 支持 `expiresInMinutes`。

创建任务返回 202 和任务 ID。进度 0–1；最多同时 4 个任务，保留最近 100 个记录，仅保存在本次进程内。取消为协作式：排队任务或批次下一项开始前停止；正在执行的单次复制/恢复会安全完成，该情况下最终状态可能仍是 succeeded，并保留 `cancelRequested: true`。

Linux 的交互预览沿用外部浏览器，状态为 awaiting-browser / external-browser；无法读取外部标签页的加载完成状态。后台 PNG 接口不受交互窗口影响。

SSE 使用相同 Bearer 认证，事件包括 preview.*、monitor.*、file.changed、backup.created、version.*、share.*、settings.updated 和 job.*。使用 HTTP 客户端流式读取，不要依赖不能设置 Authorization 的原生 EventSource。重连可传 `Last-Event-ID`，最多回放最近 256 条；游标过期返回 409，应重新查询状态后无游标连接。每 10 秒发送心跳；慢连接会断开，进程重启后事件 ID 重置。
