---
sidebar_position: 3
---

# 文件监控与自动快照

监控模块只负责任务和调度，快照模块负责复制、提交、查询和清理。两者通过注入协作，构造函数不启动监听。

## 任务与状态

`MonitManager` 从 `settings.json` 的 `monitorTasks` 读取任务。配置要求 `_schemaVersion: 1`，任务使用持久 UUID；`enabled` 表示用户期望，`runtimeStatus` 表示实际状态。启动、停止和失败互相区分。

任务列表只读，页面订阅 revision 变化。移除任务会停止监听并归档身份，快照继续保留；重新添加相同路径会复用归档身份。不读取旧 config.json 或 monitFiles。

## 调度

监听目标文件所在目录，只处理目标路径事件。150 毫秒合并事件；最小备份间隔从上次成功快照计算。复制期间发生的新变化会安排后续复制。失败保留待处理状态，两秒后重试，不推进成功时间。监听异常会尝试重新建立监听。

`monitorRate` 默认 5 分钟，`monitorMaxSize` 默认 50。时钟、监听器和快照操作可注入，调度测试采用模拟时钟。

## 快照归属与保留

新目录为 `<源目录>/.vertree/snapshots/<任务 UUID>`，内容文件以快照 UUID 命名，JSON 清单作为提交标记。清单记录任务、源路径、内容文件、时间和大小。

提交成功后，按创建时间只清理本任务验证通过的旧快照，至少保留一份。清理失败独立报告；损坏清单、未知文件与旧 `_bak` 目录不参与读取或删除。清理按钮也只删除已识别的本任务快照。

手动版本和自动快照使用同一个写入协调器，按源目录串行处理相互冲突的操作。退出时取消监听和定时器，等待正在进行的复制完成。

## HTTP 接口

- `GET/POST /api/v1/monitor-tasks`
- `PATCH/DELETE /api/v1/monitor-tasks/{id}`，其中 id 是任务 UUID
- `GET /api/v1/monitor-tasks/{id}/snapshots`
- `GET /api/v1/snapshots?path=...`
- `POST /api/v1/monitor-tasks/{id}/verification-writes`，仅用于专用测试文件

手动版本通过 `GET/POST /api/v1/versions` 操作，与自动快照分开。旧 backups 路由不保留。
