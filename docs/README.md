# Vertree documentation

站点使用 Docusaurus。以下命令从本目录运行，建议 Node.js 24：

```bash
npm ci
npm start
npm run build
```

## 内容结构

| 目录 | 内容 |
| --- | --- |
| `docs/intro.md` | 按任务查找的文档首页 |
| `docs/tutorial-usage` | 安装、备份监控、预览格式、系统入口、分享、排障 |
| `docs/tutorial-develop` | 构建、版本树、监控、设计取舍、规划、API、预览架构 |
| `docs/macos.md`、`docs/linux.md` | 平台差异与依赖 |
| `src/pages`、`src/components/HomepageFeatures` | 官网首页与功能入口 |
| `blog` | 版本更新记录 |
| `static` | 图片、站点公告和静态资源 |
| `build` | 静态产物；当前仓库跟踪此目录，提交时同步更新 |

## 写作与核对

已落地的模块边界、不兼容变更与后续扩展规则见[长期演进架构](architecture-evolution.md)。

用户指南按实际操作组织，不混入内部组件名和开发日志。格式表区分已注册扩展名、实际展示内容和已知限制。开发文档记录最终实现，历史审计留在专门文件中。

修改功能后检查使用步骤、CLI、平台差异、格式边界和排障是否一致。涉及代码路径、默认值或 API 时对照源码与运行实例 OpenAPI，避免从旧说明复制过时行为。

站点构建对失效链接报错。新增页面使用稳定文件名；修改栏目标签时保留旧栏目 slug，避免原有外链失效。构建通过后检查主要页面和窄屏表格滚动。

## 图片

Logo 统一使用 `assets/img/logo/logo.png` 和 `logo.ico`（相对于仓库根目录）。官网通过静态目录配置直接读取它们；不要在 `docs/static` 新增 Logo 副本。平台尺寸资源的生成方式见 [Logo 资源](logo-assets.md)。

仓库根目录提供 `python tools/update_doc_images.py`，通过受控开发进程与应用 API 生成截图。使用标准样例和浅色主题，提交前实际检查图片。界面未重新截图时，不把旧画面标作当前版本的验收证据。

## 公告

`static/announcement.json` 会发布为 `https://vertree.w0fv1.dev/announcement.json`。应用在公告未过期且未被忽略时显示内容。

- `uuid`：每次新公告使用不同标识。
- `content`：简洁、面向用户的变化说明。
- `expiresAt`：带时区的有效期。
- `link`：可选的 HTTP/HTTPS 绝对地址，有效时显示跳转按钮。

## 部署

main 分支推送触发 `.github/workflows/static.yml`，CI 执行 npm ci、生产构建和 GitHub Pages 部署。发布应用时同步更新 README、首页、更新日志和公告，再确认 Pages job 完成。

官方地址为 `https://vertree.w0fv1.dev/`。应用内局域网分享还依赖站点的 `/f` 页面，修改导航或内容时应保留该路由。
