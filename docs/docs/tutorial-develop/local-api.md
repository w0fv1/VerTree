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
