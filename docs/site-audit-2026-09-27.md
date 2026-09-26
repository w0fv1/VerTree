# 官网、文档与首页审计：3.0.0

最终本地核对：2026-09-27T07:35:24+08:00。此记录描述发布候选的本地验证，不以本地成功代替 GitHub Release 或 Pages 部署成功。

## 范围与结果

- 官网生产产物 44 个 HTML 路由，站内路径、锚点、资源与基本元数据检查 0 个问题。
- 浏览器 178 项检查，0 项失败：每页桌面/手机、浅色/深色布局，另含移动导航和隔离模拟的分享选路检查。
- 198 项 Flutter 测试通过，静态分析与架构检查通过；原生安全测试、5 组进程/协议测试、Explorer 菜单契约与 Windows Release 构建通过。
- 旧站 33 个 HTML 路径全部保留。新增功能页、下载页、独立用户指南与本次发布说明；历史文章保留原 slug 和事件时点。
- 真实应用截图来自隔离配置和专用样例；没有截图真实监控任务，没有删除用户工作文件或结束用户程序。

## 首页尺寸

背景宽度为可用宽度的 76%，优选最小 360、最大 640 个逻辑像素；可用空间不足时让位于窗口边界。品牌区与按钮行间距为 40，按钮默认仍为 32 高。窄窗口或大字号使用滚动/换行，不增加按钮尺寸来补偿间距。10 句文案切换不决定卡片宽度。

## 逐页清单

| 页面 | 本次审计与改进 | 最终检查 |
| --- | --- | --- |
| 没有找到这个页面 ／ Vertree 维树<br>`/404.html` | 加入清晰的缺失页面说明、首页/文档入口，并修复深色次按钮对比度。 | 通过 |
| Vertree 1.1.0：从版本树直接预览文件 ／ Vertree 维树<br>`/blog/1-1-0-file-preview/` | 历史发布说明保留原版本事实；加历史状态提示与当前指南入口，统一文字、链接和代码高亮。 | 通过 |
| Vertree 1.1.4：修复任务栏图标与退出卡顿 ／ Vertree 维树<br>`/blog/1-1-4-windows-fixes/` | 历史发布说明保留原版本事实；加历史状态提示与当前指南入口，统一文字、链接和代码高亮。 | 通过 |
| Vertree 1.2.0：文件预览图与本机自动化 API ／ Vertree 维树<br>`/blog/1-2-0-preview-image-api/` | 历史发布说明保留原版本事实；加历史状态提示与当前指南入口，统一文字、链接和代码高亮。 | 通过 |
| Vertree 2.0.0：版本、快照与监控架构升级 ／ Vertree 维树<br>`/blog/2-0-0-architecture/` | 历史发布说明保留原版本事实；加历史状态提示与当前指南入口，统一文字、链接和代码高亮。 | 通过 |
| Vertree 3.0.0：文件工具、首页与文档更新 ／ Vertree 维树<br>`/blog/3-0-0-file-tools/` | 新增本次大版本说明，清晰列出使用变化、永久删除风险和升级入口。 | 通过 |
| 历史博文 ／ Vertree 维树<br>`/blog/archive/` | 修复归档首屏标题对比度，沿用稳定历史路径。 | 通过 |
| 作者 ／ Vertree 维树<br>`/blog/authors/` | 补充页面描述并统一作者索引排版。 | 通过 |
| w0fv1.dev - 6 篇博文 ／ Vertree 维树<br>`/blog/authors/w-0-fv-1-dev/` | 补充作者页描述，去掉不完整署名说明，保留作者身份与文章关联。 | 通过 |
| 更新与设计记录 ／ Vertree 维树<br>`/blog/` | 统一列表、摘要与正文链接样式，新增发布记录。 | 通过 |
| 1 篇博文 含有标签「设计与理念」 ／ Vertree 维树<br>`/blog/tags/hello/` | 保留旧标签路径，标签改为设计与理念，移除 Hello tag description。 | 通过 |
| 标签 ／ Vertree 维树<br>`/blog/tags/` | 补充索引描述；将 Hello 模板标签改成产品相关文字而不改变 slug。 | 通过 |
| 为什么做一个单文件版本管理工具 ／ Vertree 维树<br>`/blog/welcome/` | 删去绝对化的革命性/每次修改保证，保留动机和普通文件副本原则。 | 通过 |
| 开发进展：Windows 文件工具与界面整理 ／ Vertree 维树<br>`/blog/windows-tools-development/` | 保留开发时点记录，增加 3.0.0 发布后续，避免把历史状态当作当前状态。 | 通过 |
| 使用指南 ／ Vertree 维树<br>`/docs/category/tutorial---使用/` | 统一栏目说明、侧栏入口和索引卡片；保留原栏目 slug，检查子页与前后导航。 | 通过 |
| 开发与架构 ／ Vertree 维树<br>`/docs/category/tutorial---开发/` | 统一栏目说明、侧栏入口和索引卡片；保留原栏目 slug，检查子页与前后导航。 | 通过 |
| 从一个文件开始 ／ Vertree 维树<br>`/docs/intro/` | 按任务提供入口，移除旧 1.1.0 首屏，纠正快照目录，标明 Windows 专有功能。 | 通过 |
| Linux 使用说明 ／ Vertree 维树<br>`/docs/linux/` | 将普通安装与开发依赖分开；核对 Files 动作、浏览器预览与托盘限制。 | 通过 |
| macOS 使用说明 ／ Vertree 维树<br>`/docs/macos/` | 区分 arm64 分发与 Intel，保留公证、Services、Dock 与浏览器引擎限制。 | 通过 |
| 设计取舍 ／ Vertree 维树<br>`/docs/tutorial-develop/design/` | 保留取舍，不把永久删除当成备份/回收站，也不混同占用查询。 | 通过 |
| 开发与构建 ／ Vertree 维树<br>`/docs/tutorial-develop/develop/` | 更新模块目录、工具链和验证命令；去掉 lib/core 等旧架构说明。 | 通过 |
| Windows 文件工具架构 ／ Vertree 维树<br>`/docs/tutorial-develop/file-tools/` | 新增原生辅助进程、范围租约、路径身份、有限并发与进程操作保护的说明。 | 通过 |
| 版本规则与显示模型 ／ Vertree 维树<br>`/docs/tutorial-develop/filetree/` | 核对 next/branch/auto、冲突、版本图和显示投影；补充范围协调。 | 通过 |
| 本机 API 与开发控制器 ／ Vertree 维树<br>`/docs/tutorial-develop/local-api/` | 保留真实 API 契约，纠正 nullable 进度与取消状态，不虚构公开 delete/kill 接口。 | 通过 |
| 监控调度与快照归属 ／ Vertree 维树<br>`/docs/tutorial-develop/monitor/` | 核对 UUID、归属清单、事件合并与重试；补充与删除的资源协调。 | 通过 |
| 文件预览架构 ／ Vertree 维树<br>`/docs/tutorial-develop/preview-architecture/` | 核对资源生命周期与删除协调，将历史测试记录与当前保证分开。 | 通过 |
| 实现状态与后续规划 ／ Vertree 维树<br>`/docs/tutorial-develop/roadmap/` | 区分 3.0.0 已实现、尚待实机验证与未来方向，不保留过时发布状态。 | 通过 |
| 右键菜单与命令行 ／ Vertree 维树<br>`/docs/tutorial-usage/entry-points/` | 两套 Windows 菜单均可逐项设置；分清单文件动作与多选文件工具，纠正平台入口差异。 | 通过 |
| 快速删除（Windows） ／ Vertree 维树<br>`/docs/tutorial-usage/fast-delete/` | 新增永久删除风险、一次确认、只读与占用处理、停止和失败项规则，不宣传通用加速倍数。 | 通过 |
| 查看与解除文件占用 ／ Vertree 维树<br>`/docs/tutorial-usage/file-locks/` | 新增独立占用诊断、管理员扫描、结束程序风险，以及不等于无损解锁的边界。 | 通过 |
| 安装与升级 ／ Vertree 维树<br>`/docs/tutorial-usage/install/` | 更新安装包版本，解释 EXE/ZIP/MSI、运行时、升级保留与旧配置边界。 | 通过 |
| 监控与自动快照 ／ Vertree 维树<br>`/docs/tutorial-usage/monitoring/` | 新增任务设置、最小间隔、快照归属、保留数量与移除任务的说明。 | 通过 |
| 文件预览与格式支持 ／ Vertree 维树<br>`/docs/tutorial-usage/preview/` | 核对格式表，区分注册格式与实际显示内容，保留大文件和专有格式限制。 | 通过 |
| 完成第一次备份 ／ Vertree 维树<br>`/docs/tutorial-usage/quick-start/` | 新增首次备份指南，步骤以磁盘上出现真实版本副本为完成条件。 | 通过 |
| 设置与配置文件 ／ Vertree 维树<br>`/docs/tutorial-usage/settings/` | 新增唯一 settings.json、主要字段、默认值、旧配置处理与临时文件边界。 | 通过 |
| 局域网分享 ／ Vertree 维树<br>`/docs/tutorial-usage/sharing/` | 缩短发送与接收步骤，区分公网选路页面和局域网文件传输，补充权限/失效排查。 | 通过 |
| 常见问题与排查 ／ Vertree 维树<br>`/docs/tutorial-usage/troubleshooting/` | 按现象排查，移除过时菜单迁移说法，补充新工具、空间释放和配置问题。 | 通过 |
| 备份、监控与版本树 ／ Vertree 维树<br>`/docs/tutorial-usage/usage/` | 简化概览，保留原链接，纠正自动快照目录和不保证每次保存留档的语义。 | 通过 |
| 版本树与分支 ／ Vertree 维树<br>`/docs/tutorial-usage/version-tree/` | 新增用户版版本树说明，区分主线、分支、备注与磁盘文件关系。 | 通过 |
| 下载与安装 ／ Vertree 维树<br>`/download/` | 按实际发行架构提供 3.0.0 安装包链接、校验文件和升级风险；区分普通安装与调试附件。 | 通过 |
| Vertree 文件分享 ／ Vertree 维树<br>`/f/` | 改善空链接/无效链接状态、提示和页面层次；不在调试日志中输出分享凭据；保留原协议。 | 通过 |
| 功能与使用场景 ／ Vertree 维树<br>`/features/` | 按文档、设计稿和脚本场景说明；区分阶段版本与自动快照，明确能力边界。 | 通过 |
| 让每一次迭代都有迹可循 ／ Vertree 维树<br>`/` | 重写首屏、下载与首次备份入口；使用真实版本树截图，分清版本管理与 Windows 文件工具。 | 通过 |
| 文档导航 ／ Vertree 维树<br>`/markdown-page/` | 将模板演示页改成有效帮助入口，保留旧路径。 | 通过 |

## 跨页修复

统一浅/深色配色、文字层级、容器宽度、导航和页脚。正文链接增加非颜色识别方式；修复归档标题、代码 token 以及深色次按钮的对比度。表格与代码块在窄屏内部滚动，不将整页横向撑开。补足作者和标签索引的 description。

## 开发与维护文档

同步核对并修改根目录中英文 README、docs/README.md、长期演进架构、Windows 文件工具实现说明、预览集成说明、上游历史审计说明与 Logo 资源说明。关键修正包括 `.vertree/snapshots/<任务 UUID>`、单一 settings.json、菜单单项选择、最终页面入口和现有模块边界。历史上游核对的固定提交与历史测试数未篡改成新结果。

## 可重复执行

静态检查：`npm --prefix docs run build` 后运行 `npm --prefix docs run audit:static`。浏览器检查需先启动仅监听 loopback 的生产预览，再运行 `npm --prefix docs run audit:browser`；详见 [站点维护](README.md)。

源码检查器位于 `docs/scripts/audit_static.py` 与 `docs/scripts/audit_browser.cjs`。Pages 部署前执行静态检查；发布流程另运行可复用的 Documentation quality 工作流。

本次机器报告和截图位于仓库忽略目录 `build/release_3_0_0/`：`validation.json`、`protocol-results.json`、`static.json`、`browser.json`、`app-screenshot-report.json`、`screenshots/` 与 `app-screenshots/`。这些本机路径不是公网下载地址。

## 不应从本次审计推导的结论

浏览器自动检查不等于完整 WCAG 认证，也不涵盖所有辅助设备。Windows 本地测试不等于 macOS/Linux 原生桌面实测；三平台编译由发布工作流另行验证。未重跑全部性能基准，不承诺 HDD、SMB、云文件或所有文件系统上的速度与兼容性。公开发布只以 Release 附件和 Pages 部署的最终状态为准。
