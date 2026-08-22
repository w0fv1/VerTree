# Vertree Docs

Vertree 的文档站使用 Docusaurus 构建，源码在 `docs/docs`，静态产物输出到 `docs/build`。

## 环境

- Node.js 18+
- npm

## 安装依赖

```bash
npm install
```

## 本地预览

```bash
npm start
```

## 构建静态站点

```bash
npm run build
```

## 主要维护文件

- `docs/docs/intro.md`
- `docs/docs/tutorial-usage/install.md`
- `docs/docs/tutorial-usage/usage.md`
- `docs/docs/macos.md`
- `docs/docs/linux.md`
- `docs/static/announcement.json`

## 公告 JSON

站点会把 `docs/static/announcement.json` 原样发布到：

```text
https://vertree.w0fv1.dev/announcement.json
```

当前应用会读取这个 JSON，并在 `uuid` 未被用户忽略、且 `expiresAt` 未过期时弹出公告。`link` 是可选字段；只有在它是合法的 `http/https` 绝对地址时，应用里才会显示“前往”按钮。格式如下：

```json
{
  "uuid": "2026-03-maintenance",
  "content": "这里填写公告正文。",
  "expiresAt": "2026-04-01T00:00:00Z",
  "link": "https://github.com/w0fv1/vertree/releases"
}
```

如果发布内容有变更，优先先改这几处，再重新构建 `docs/build`。
