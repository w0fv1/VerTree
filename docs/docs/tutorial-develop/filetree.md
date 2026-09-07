---
sidebar_position: 2
---

# 版本规则、版本图与显示模型

版本模块位于 `lib/modules/versions`。文件命名、查询和修改规则统一由模块提供，UI 的布局模型位于 `lib/adapters/ui/versions`。

## 文件名与版本号

文件名格式为 `<name>[#label].<version>.<ext>`，例如 `story.0.1.txt`、`story#baseline.0.1.txt`、`story#optionA.0.1-1.0.txt`。未标版本号的普通文件默认视为 0.0。

`VersionName` 解析命名和校验标签，`FileVersion` 处理不可变的版本段、比较和分支关系。两个值对象都不执行文件 I/O。标签禁止路径分隔符、保留字符、控制字符和会造成命名歧义的字符。

## 统一命令

`VersionCommands.create` 提供 next、branch 和 auto 模式。auto 在后继版本已占用时选择新的分支；分配和发布使用共享写入协调器，UI、HTTP、CLI 和托盘调用相同规则。

`renameLabel` 返回新的文件路径；UI 更新显示引用后，后续备份继续使用新路径。改名不能覆盖已有文件。

`restore` 在覆盖已有目标前创建 before-restore 版本，并检查目标是否在操作过程中变化。

## 查询与异常数据

`VersionCatalog` 扫描同目录同族文件，返回 `VersionGraph` 的 entries、parents 和 diagnostics。重复版本或缺失父节点会显式报告，完整 entries 保留异常文件。

HTTP 的 `/api/v1/version-trees` 直接映射版本图，不引用 Flutter 布局对象。

## UI 投影

`buildTree` 将版本图投影为 `FileNode`。节点维护显示关系，分支布局数据从关系推导；`FileMeta` 提供不可变路径与属性。节点和元数据不再提供复制、改名或备份方法。

版本图不完整时，页面显示诊断，已有可连接部分仍可查看。API 的完整 entries 可用于排查未连入显示树的文件。

## 验证

测试覆盖版本号规则、标准样例树、无关文件过滤、缺失文件、并发创建、重命名后继续备份和同名目标保护。结构变动需运行 `dart run tools/check_architecture.dart`，禁止业务模块反向依赖 UI。
