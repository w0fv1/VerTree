# Vertree 1.0.0

Vertree `1.0.0` 是首个稳定正式版，整理并确认 Windows、macOS、Linux 桌面发布链路，同时把本机 HTTP API、OpenAPI 文档和局域网文件分享能力纳入稳定发布说明。

## 本次重点

- Windows 桌面发布提供安装包、便携包、MSI、符号包和 Win11 菜单调试包
- macOS 桌面发布提供带架构标识的 `zip` / `dmg` 和符号包
- Linux 桌面发布提供便携 `tar.gz`、Debian / Ubuntu `.deb` 和 RPM 包
- 本机 HTTP API 保持 loopback-only，并提供 OpenAPI 文档、监控任务控制、备份、版本树和截图接口
- 局域网文件分享可从版本树节点生成短分享链接、二维码和自动选路分享页
- 文档站、README、官网公告和应用内版本检查同步更新到 `1.0.0`

## 发布说明

- 这是正式稳定版，不会以 `prerelease` 形式发布
- 若通过 tag 触发发布，请使用 `V1.0.0` 或 `v1.0.0`
