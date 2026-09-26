# Windows 文件工具：实现与验证

实现说明审计：2026-09-27，对应 3.0.0。参数和测量记录需结合具体平台与测试条件阅读，不代表所有设备上的性能保证。

本次能力：快速永久删除，以及 PowerToys File Locksmith 风格的本机文件占用诊断。移动、复制、回收站替代、安全擦除、驱动级解锁不在范围内。

## 使用与发布状态

Windows 文件工具从 3.0.0 开始提供。用户指南见 [快速删除](docs/tutorial-usage/fast-delete.md) 与 [解除占用](docs/tutorial-usage/file-locks.md)。

两个独立页面只从资源管理器右键菜单进入；首页和标题栏没有文件工具快捷入口。目标通过右键多选带入，或直接点击页面目标卡片选择，不提供路径输入框、并发选择、会话任务或本机历史板块。

删除只有一个闪电“删除”动作，确认框明确永久删除、不进回收站，以及自动清除只读、结束可处理占用程序的风险。UI 使用 `DeletionOptions.lightning()`，确认后有限轮次处理真正失败项并重试。没有逐项额外勾选，也不承诺清除所有系统级阻碍。

当前 UI 提供停止，不展示暂停/继续控件。停止不是撤销，已删除内容不会恢复。失败项保留错误类型与身份约束；新对象不继承旧授权，重启不自动续删。

占用页面参考 File Locksmith：按进程卡片展示名称、PID、路径、用户与相关文件，可刷新或管理员扫描。结束某个进程需确认，可能影响其打开的全部文件；页面不会删除目标。用户应优先在原程序保存并关闭，当前页面不提供正常关闭按钮。

管理员能力只提升受限辅助进程，不长期提权主程序，也不开放提权删除。关键、受保护、服务会话、无法验证及 VerTree 自身等进程不可随意处理。没有结束整个进程树或强关别人的单个文件句柄的入口。

### 命令行与资源管理器

以下命令只打开界面，不绕过确认框：

```powershell
.\vertree.exe file-tools
.\vertree.exe fast-delete "C:\work\build" "C:\work\large.bin"
.\vertree.exe unlock "C:\work\build"
```

经典菜单和 Windows 11 菜单提供文件和目录入口。文件工具可使用多选；原有备份／预览等单文件业务不会误接收整个多选列表。Shell DLL 只读取有界的顶层选择并生成每次调用独立的临时清单，随后启动应用，不在 Explorer 内枚举目录、删除文件或扫描进程。最多接受 1,024 个顶层选择；具体 Explorer 菜单模型也可能施加自己的选择数量限制。

临时选择清单使用版本、所有者标识、GUID 文件名、大小及有效期检查；读取后只消费这次调用的清单。它本身不构成永久删除授权。

## 模块边界

| 位置 | 职责 |
| --- | --- |
| `lib/modules/deletion` | 准备目标、删除命令、结果模型、使用租约端口 |
| `lib/modules/file_locks` | 占用查询与显式进程操作命令 |
| `lib/file_access/file_access.dart` | 共享的文件、目录条目、子树和任务范围协调 |
| `lib/file_access/infrastructure/windows_file_worker.dart` | 原生进程协议、设备预算、超时及退出等待 |
| `lib/app/file_tools_backend.dart` | 依赖装配、监控／预览／分享使用租约 |
| `lib/adapters/ui/file_tools_controller.dart` | 界面状态、现有作业调度适配 |
| `lib/view/page/delete_page.dart`、`file_locks_page.dart` | 独立的删除与占用页面 |
| `windows/file_tools` | C++17 删除引擎、路径守卫、句柄／模块查询和受限 UAC 代理 |

业务 domain/application/ports 不导入 Flutter、dart:io 或基础设施实现。现有单 package 与架构检查规则保持不变。快照清理仍使用原有所有权校验，不把通用递归删除引擎用于猜测清理未知快照文件。

### 写入与资源协调

`MutationScope.file`、`directoryEntries`、`subtree`、`task` 表示不同资源语义。冲突按路径组件判断，而不是字符串前缀猜测；例如 `C:\a` 不包含 `C:\abc`。Windows 的大小写比较保守地串行化，允许多锁一些，不放松删除范围。

删除先预留范围，拒绝后来进入的重叠写入，再等待已接收的版本／快照等操作排空。祖先目录删除与子目录写入会冲突。多个资源一次申请，冲突任务 FIFO，无嵌套锁。只有原生进程确实退出，Dart 调用才返回并释放范围。

相关监控暂停运行，但不篡改持久化的 enabled 意愿。完成后只对仍存在且身份未替换的文件恢复监控。预览创建纳入协调；相关预览关闭。相关 LAN 分享被撤销，正在读取源文件的流被取消；无关监控、预览和分享不受影响。

这些是同一应用实例内的协调，不提供对外部编辑器的事务隔离。原生路径守卫承担对象身份和链接边界验证。

## 原生删除算法

1. 用句柄验证顶层目标、卷／文件 ID 和创建时间，保留祖先链身份。
2. 从卷或共享根开始固定普通父目录句柄；每一段相对于已验证父句柄打开。不穿越 reparse 祖先。8.3／别名的最终路径再次检查保护范围。
3. 64 KiB 批量读取目录元数据，使用 `FileIdExtdDirectoryInfo`，支持时退到 `FileIdBothDirectoryInfo`。不把整棵目录树加载为 List。
4. 显式目录栈限制深度 256；文件队列最多 4,096 项，同时限制 16 MiB 记录预算。每个目录只保留有界枚举游标和活动子项状态。
5. 打开枚举项后再次验证其身份，使用 `FileDispositionInfo` 提交删除。完成子项后才删除父目录。外部不断新增内容会留下明确失败，不无限扫描。
6. 单个大文件走同样的元数据／删除路径，不分块读取或覆盖正文。

线程起始预算是未知／寻道设备 1、固态设备 4、网络目标 2，运行时在有界范围根据完成率和延迟调整。Dart 端统一分配最多 8 个删除工作线程预算；映射到同一设备的独立作业不各自抢占一套无限线程。设备无法识别时采用保守共享预算。

并行不是必然更快。基准必须同时保留串行原生、自动并发和 Dart 递归基线；不能只挑最快的一个结果宣称普遍加速。

### 链接、失败与空间语义

符号链接和普通 junction 只删除链接本身。卷挂载点以及未知／云文件 reparse 类型明确拒绝或保留，不做“看起来像目录就递归”的处理。文件系统无法提供可用稳定身份时失败关闭，不退化成仅字符串校验。

共享冲突、ACL 权限、只读、设备不可用、身份变化、非空目录、删除待关闭等使用不同错误码。取消或发生错误不能把部分结果改成全部成功。

提交删除后可能仍在等待其他句柄关闭。实现确认名称移除，无法确认时保留 pending 语义。`logicalBytesProcessed` 是已处理文件的逻辑大小，不等于实际释放的磁盘空间。不会展示未经测量的“已释放 XX GB”。

默认不执行整树预扫描，`percent` 和 `totalItems` 可以为空。成功后百分比才终结为 1。任务报告包括文件／目录成功数、失败数、发现数、首次实际删除时间、工作集和采样句柄峰值；采样峰值不是所有瞬间的精确句柄峰值。

## 占用诊断与隔离

参考 PowerToys File Locksmith 的句柄与已加载模块两个来源，实现独立的 C++ 查询器，不依赖 PowerToys 安装或二进制。目标目录与系统中打开的对象路径按目录边界匹配，不递归读取选中目录里的几十万个文件。文件 ID 补充识别单文件硬链接。

系统句柄表最大 64 MiB，进程句柄缓存、结果进程数、每进程文件数和输出字节数都有上限。达到预算、权限拒绝或查询超时会返回不完整结果。增量发现会立即传回主程序，后续查询卡住时不会丢失已有结果。

句柄名称查询可能阻塞，因此所有查询都在辅助进程内运行。主程序监测真正的进度及期限；取消后等待退出，必要时结束的是本次启动的辅助进程，不是占用文件的用户应用。辅助进程也监测宿主生命期；主程序意外退出不会留下无期限继续删除的孤儿进程。

UAC 使用随机私有命名管道：限制当前用户／管理员／系统，拒绝远程管道客户端，核对双方 PID、创建时间、可执行路径和随机握手。特权接口只接受扫描和单进程操作，不接受任意命令行或删除目标。管理员进程操作还有本地原生确认框，默认否。

## 日志、重试与退出

记录位于应用配置目录的 `file-tools/jobs/<UUID>/`。`intent.json` 在开始前落盘；`progress.json` 节流更新；`failures.jsonl` 只记失败项；`result.json` 保存终结状态。成功项只聚合，不逐项同步写盘。失败报告最大 32 MiB，界面预览最多 100 条并有字节上限，超过限制停止新增工作而不是耗尽内存。

同会话失败报告有 SHA-256 完整性检查，原生还校验每条重试记录位于原来确认的身份范围。重试不递归枚举，只尝试记录过的原失败对象与父目录。关闭应用或崩溃后，历史记录不自动续删，不把旧路径当作持续授权。没有事务回滚或文件恢复功能。

保留最多 100 个任务目录。达到上限后，可从配置目录定位内部报告并清理已经审阅的报告目录；当前没有历史记录 UI；不会自动删除未审阅记录、未知文件或损坏记录。

## 构建和安装包

正常工具链：Flutter stable、Visual Studio C++ Desktop workload、CMake、NuGet CLI。原生 helper 通过 `windows/CMakeLists.txt` 随主应用构建，安装到 runner bundle 根目录；原有 ZIP、Inno、WiX 和 MSIX 的 bundle 采集路径会包含它。测试进程和 native tests 不安装进 bundle。nlohmann/json 的 MIT 许可随 `data/licenses/` 打包。

网络不可用且所有精确版本的依赖已在本机 NuGet 缓存中时，可显式使用：

```powershell
$env:VERTREE_NUGET_CACHE_ONLY = '1'
flutter build windows --release
```

这不是一般 NuGet 替代品。`tools/nuget_cache_adapter.py` 只处理项目插件需要的精确版本 install 调用，验证缓存包 SHA-512 和路径范围，只写本仓库 build 目录，不联网、不改缓存、不改变全局代理配置。缓存缺失或内容不同明确失败。正常构建不设置该环境变量。

Windows 11 与完整 MSIX 共用 sparse manifest；新增目录关联和两个独立叶命令 CLSID。Inno 卸载清理增加本功能的文件／目录菜单与 CLSID。不要为了重新构建开发 DLL 而结束用户的 Explorer 或其他任意进程。

## 验证命令

```powershell
dart run tools/check_architecture.dart
flutter analyze
flutter test
cmake -S windows/file_tools -B build/file_tools_native -A x64
cmake --build build/file_tools_native --config Release
ctest --test-dir build/file_tools_native -C Release --output-on-failure
python tools/test_windows_file_tools.py
cmake -S windows/context_menu/tests -B build/file_tools_menu_tests -A x64
cmake --build build/file_tools_menu_tests --config Release
.\build\file_tools_menu_tests\Release\vertree_menu_tests.exe
```

原生测试覆盖有界并行树、顶层／祖先替换、junction 边界、部分失败和精确重试、只读许可、50 GiB **稀疏**文件、暂停取消、危险根和进程守卫。进程集成测试覆盖真实自建测试进程的文件句柄和模块占用、PID 创建时间、正常关闭不升级、明确结束后的退出验证、UTF-8／长路径及失败清单越界拒绝。

所有删除数据都是新建的临时测试目录，进程操作仅指向本次启动的专用 holder 子进程；CI 和开发脚本不结束用户的应用。

完整基准包含真实写入的大文件和最多几十万小文件，需显式启动：

```powershell
python tools/test_windows_file_tools.py --benchmark --counts 10000,100000,300000 --real-gib 2 --dart C:\flutter\bin\cache\dart-sdk\bin\dart.exe
```

每轮重新创建等价数据；创建耗时、prepare、删除外部总耗时和引擎耗时分开记录。不清空操作系统缓存、不禁用安全软件。单次固定顺序测试不能推导所有设备上的加速倍数。HDD、SMB、ReFS、云同步盘以及 UAC 的特定策略需要各自机器上的验证，不能用本地 NTFS 结果代替。

### 隔离的界面验证

`VERTREE_ISOLATED_PROFILE` 可以指向系统临时目录下预先创建的 `VerTree-Smoke-*` 普通目录。该模式使用独立配置和单实例标识，跳过启动时的菜单重注册及公告／启动统计。正常用户配置不变。测试开始前写入 `initialSetupPrompted: true`，不要在 smoke profile 中主动安装系统菜单。

## 参考与许可

- PowerToys File Locksmith 参考提交：`dd65f4017eed298e3e6d898e24fc55f9c224b069`，MIT。
- nlohmann/json v3.11.3，MIT，来源和固定 SHA-256 见 `windows/file_tools/third_party/README.md`。
- Windows 原生 API：`NtCreateFile`、`GetFileInformationByHandleEx`、`FileDispositionInfo`、`GetFinalPathNameByHandleW`、`DuplicateHandle`、`EnumProcessModulesEx`、`IsProcessCritical`、`TerminateProcess`。

实现不承诺越过系统保护、云占位文件提供者或远程服务器权限；不使用内核驱动，不修改 MFT，不执行安全擦除。
