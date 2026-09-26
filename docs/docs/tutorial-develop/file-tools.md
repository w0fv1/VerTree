---
title: Windows 文件工具架构
description: 有界删除、对象身份、占用检测与用户确认的模块和进程边界。
sidebar_position: 8
---

# Windows 文件工具架构

:::info Windows 3.0.0
本页对应 Windows 3.0.0 文件工具。用户流程见[快速删除](../tutorial-usage/fast-delete.md)和[解除占用](../tutorial-usage/file-locks.md)。
:::

## 入口与职责

| 层 | 职责 |
| --- | --- |
| `delete_page.dart` / `file_locks_page.dart` | 独立页面，选择、确认和当前操作反馈 |
| `modules/deletion` / `modules/file_locks` | 业务命令、结构化结果和端口 |
| `file_access.dart` | 文件、目录条目、子树与任务范围冲突协调 |
| `windows_file_worker.dart` | 辅助进程协议、预算、期限与退出等待 |
| `windows/file_tools` | 原生目录枚举、身份验证、删除与进程诊断 |
| Explorer 菜单 DLL | 只传递有界顶层选择，不在资源管理器内做删除 |

Dart 调用按任务传入目标，聚合进度返回；不逐文件调用 UI channel。原生进程卡住时隔离其故障，不拖住 Flutter 事件循环。

## 删除流水线

先验证顶层目标身份并预留变更范围，等待相关写入排空，同时释放本应用的相关监控、预览或分享资源。批量枚举进入有界队列，处理子项后才删除父目录。

大文件不读取正文、不做内容哈希或覆盖清零。小文件队列同时限制数量与字节；文件队列上限 4,096、记录预算 16 MiB，目录栈深度预算 256。默认按设备预算调整并发，不用 CPU 核数无限开线程。

少量失败不阻塞其他独立分支。一次确认后的自动阻碍处理最多执行有限轮次，仅对原失败记录重试；不会重新遍历已完成分支，也不会追删新出现的同名文件。

## 路径安全不是字符串前缀

固定父目录句柄，并相对打开和核对对象身份。普通链接只删除链接，不进入目标；重解析祖先、未知云占位对象或无法获得稳定身份时拒绝继续。保护系统根、程序自身关键路径，权限失败不自动修改 ACL 或夺取所有权。

内部协调不构成外部编辑器的事务隔离；原生身份检查仍是必要边界。停止不回滚，崩溃后历史意图不自动续删。

## 占用查询与进程操作

扫描文件句柄与已加载模块，再按目标文件或目录边界聚合进程，不先枚举目标目录中的全部文件。预算、权限与期限会影响结果完整性，空结果不能证明不存在占用。

结束前核对 PID、创建时间和实际使用关系。管理员能力由受限辅助进程承担，只接受明确的扫描和进程动作，不接受任意命令或提权删除。关键、受保护、无法验证的进程与本应用自身不被自动结束。

独立占用页要求显式结束任务确认；删除页的一次确认中明确包含可处理进程终止风险。两种入口不混用授权。

## 结果、报告与界面

进度总数可未知。succeeded、partial、cancelled、interrupted 分开表达，已处理逻辑字节不是已释放磁盘容量。成功项聚合，失败项写入有界报告。

内部报告存放于配置目录的 `file-tools/jobs/<UUID>`，不属于另一个应用设置文件。当前 UI 没有会话历史或本机记录板块，也不会从报告恢复永久删除授权。

## 复现验证

```powershell
dart run tools/check_architecture.dart
flutter analyze
flutter test
cmake -S windows/file_tools -B build/file_tools_native -A x64
cmake --build build/file_tools_native --config Release
ctest --test-dir build/file_tools_native -C Release --output-on-failure
python tools/test_windows_file_tools.py
```

基准通过显式 `--benchmark` 启用，只用新建临时目录与专用 holder 测试进程。分别记录数据创建、准备、删除与内存峰值；普通文件与稀疏文件、大文件与海量小文件分别评价。不关闭安全软件，不清空系统缓存，也不结束用户的工作程序。

更完整的参数、故障注入和许可记录位于 3.0.0 的 `docs/windows-file-tools.md`。请在对应版本标签下阅读，旧发布包可能不包含这一模块。
