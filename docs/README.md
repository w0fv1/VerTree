# 官网与文档维护

`docs/` 是官网源码，不是另一份应用配置。Docusaurus 3.10.0 + React，中文站点部署到 `https://vertree.w0fv1.dev/`。应用使用 Flutter，两者分别构建。

## 本地开发与生产预览

建议 Node.js 24，最低约束见 `package.json`；静态审计脚本另需要 Python 3 标准库。

```bash
cd docs
npm ci
npm start
```

生产构建与审计：

```bash
npm run build
npm run audit:static
npm run serve -- --host 127.0.0.1 --port 33030
```

保持本机预览服务运行，在另一个终端执行：

```bash
# 首次运行浏览器审计时安装独立测试浏览器
npx playwright install chromium
# Windows 默认使用已安装的 Edge；其他环境指定 chromium
VERTREE_BROWSER_CHANNEL=chromium npm run audit:browser
```

上面环境变量语法用于 POSIX shell。PowerShell 使用 `$env:VERTREE_BROWSER_CHANNEL='chromium'` 后运行 `npm run audit:browser`；已有 Edge 可不设置。测试浏览器独立启动，不连接用户已有的浏览器会话。

`VERTREE_DOCS_URL` 默认 `http://127.0.0.1:33030`，只能指向受控本机预览。报告默认位于仓库 `build/site-audit/`；可用 `VERTREE_AUDIT_DIR` 与 `VERTREE_STATIC_AUDIT` 指定输出目录和静态清单。

## 逐页检查什么

静态脚本枚举所有构建后的 HTML，不只检查手写页面。检查标题、描述、文档 h1、替代文字、本地资源、站内链接和锚点。Docusaurus 本身也把损坏 Markdown 图片和链接设为构建错误。

浏览器脚本检查每个路由的桌面 / 手机尺寸、浅色 / 深色、水平溢出、图片加载、脚本异常与 WCAG A/AA 自动检查，并保留截图。另验证手机导航、分享缺少或损坏链接，以及完整链接的解析和跳转。分享测试拦截测试地址，不访问真实局域网。

自动检查不是人工可用性审查的替代。提交前仍需逐页查看截图中的排版、阅读顺序、按钮文案与实际产品是否一致。当前测试基于 Chromium / Edge，不代表 Safari、Firefox 或真实手机已验收。

## 页面与数据的归属

| 目录 | 内容 |
| --- | --- |
| `src/pages` | 官网首页、功能、下载、保留的旧导航入口与 `/f` 分享页 |
| `docs` | 用户指南、平台说明与开发文档 |
| `blog` | 历史更新与明确标注的开发进展 |
| `src/css/custom.css` | 共享颜色、文字、文档、表格、菜单与可访问样式 |
| `src/theme` | 404 与生成式索引页的少量包装，不复制整个主题 |
| `static/img` | 专用样例的真实应用截图 |
| `scripts` | 可重复的静态和浏览器审计 |
| `build` | 当前仓库跟踪的生产输出，构建后同步检查 |

保持既有文档路径、分类 slug、博客 slug 和 `/f` 协议稳定。旧模板 `/markdown-page` 已改成文档导航，不再展示模板内容。品牌 PNG/ICO 直接来自 `../assets/img/logo`，不要再复制一套 Logo。

## 文案与发布边界

每页先说要完成什么，再解释步骤与失败。手动版本、自动快照和临时预览快照分开描述。监控目录使用 `.vertree/snapshots/<任务 UUID>`；`*_bak` 只在历史兼容说明中出现。

文件工具仍属开发分支时，在首页、下载和相关文档明确标注，不给旧正式版本贴上新功能。下载页固定版本是“已核对版本”，另提供 GitHub 最新发布入口；发布时核对附件架构、名称、签名和 SHA256SUMS 后再更新。

历史更新保留当时的验证记录，增加时间语境，不把旧测试数或旧接口当作当前保证。新开发进展不伪装成正式版本公告，也不顺带修改 `static/announcement.json`。

## 应用截图

优先使用隔离配置与专门创建的测试文件，经受控本机 API 导出应用画面，而不是截取用户桌面。不要出现 Token、真实分享链接、私人文件内容或工作软件窗口。`tools/update_doc_images.py` 是常规入口；隔离模式规则见 `docs/windows-file-tools.md`。

截图后核对主题、尺寸、文件名与控件，不能仅因为 PNG 文件存在就发布。版本树图应来自当前程序，文字和操作区不能用演示 HTML 冒充。

## 发布

`.github/workflows/static.yml` 在 main 更新后构建并部署 GitHub Pages。合并前执行构建、审计和内容检查。本地 `docs/build`、本地预览和公网部署是三个状态，不应混称“已上线”。

此轮范围与逐页结论见 [逐页审计记录](site-audit-2026-09-27.md)。
