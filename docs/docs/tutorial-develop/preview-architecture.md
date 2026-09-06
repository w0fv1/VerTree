---
sidebar_position: 7
---

# 文件预览架构

用户操作与格式矩阵见[文件预览与格式支持](../tutorial-usage/preview.md)。这里说明 Flutter、Office-Viewer 和本机服务之间的边界。

## Flutter 如何复用 Office-Viewer

Office-Viewer 自身是 Tauri 应用，但格式解析和渲染在 React 前端中实现。Vertree 直接导入这些前端模块，以独立只读入口打包；运行 Vertree 时不启动 Tauri，也不调用上游 Rust 命令。

```text
版本树 / CLI / Windows 菜单
                ↓
     PreviewDialogController
                ↓
         FilePreviewDialog
           ↙          ↘
FilePreviewSession     WebView / 浏览器
   文件快照               ↓
   HTTP Range ← web/office_preview 只读宿主
                          ↓
               Office-Viewer registry / Preview / 解析器
```

| 组件 | 职责 |
| --- | --- |
| `vendor/office-viewer` | Git 子模块固定通用预览代码版本 |
| `web/office_preview` | 路由、只读宿主、依赖锁定、构建入口 |
| `tools/build_office_preview.py` | 初始化子模块、npm ci、生成离线资源 |
| `assets/office_viewer` | Flutter 随包携带的 HTML、JS、Worker 和第三方声明 |
| `lib/service/file_preview_session.dart` | 临时快照、本机资源路由、Range 与回收 |
| `lib/view/module/preview_dialog_controller.dart` | 预览路由唯一性与连续请求顺序 |
| `lib/view/module/file_preview_dialog.dart` | WebView、加载状态、系统打开与关闭操作 |

## 会话生命周期

每次打开文件会创建临时磁盘快照和带随机 Token 的 loopback 地址。页面只可访问本次会话下的文件和内置资源；关闭时销毁会话并删除快照。

控制器跟踪实际预览路由。新请求先移除旧路由，等待页面退出与销毁后再打开；若关闭期间又来了更新请求，只显示最新请求。其他类型的对话框不受影响。

Windows 共享应用内 WebView 环境，数据目录放在用户应用支持目录，支持安装目录只读的场景。macOS 使用 WKWebView，Linux 通过外部浏览器打开会话地址。浏览器标签页不属于 Flutter 路由，关闭会话后可能仍留有已渲染画面。

## 按 URL 与按完整内容加载

格式注册器可通过 `loadUrl` 声明 URL 加载能力。普通图片、字体、音视频和 PDF 无须先把整个文件读入 Dart 与 JavaScript；Parquet 根据页和行组按需读取。

会话提供 HEAD、ETag、If-Range 和 HTTP Range，处理正常分段、尾部分段及越界请求。无效或不满足的范围不会返回伪造的文件片段。

Office 文档、压缩包、文本和部分转换器仍需要完整字节内容。磁盘快照也需要一次复制。因此“无固定 64 MiB 上限”不等于恒定内存或无限文件大小。

## 访问约束

预览服务只绑定 loopback，校验请求的 Host、Origin 和 Fetch Metadata，不提供目录枚举或写入接口。CSP 限制外部网络资源；HTML、邮件、SVG 等内容经过清理，不把文件中的脚本交给页面执行。

预览、自动化 API 和局域网分享相互独立。预览地址的 Token 只用于当前会话，不复用自动化 API Token，也不创建 LAN 分享。

## 扩展一种格式

1. 在 Office-Viewer 注册扩展名并实现解析或渲染。可按 URL 读取时提供 `loadUrl`。
2. 添加真实最小样例和对异常输入的测试，处理加密、损坏及不支持的文件结构。
3. 对异步渲染、Worker、Blob URL 注册关闭时的清理；避免旧文件的迟到结果覆盖新文件。
4. 在 Vertree 同步运行时依赖与必要的类型解析路径，然后重新构建 assets。
5. 验证独立 Office-Viewer 与 Vertree 宿主，最后在目标平台检查原生 WebView。

格式支持应说明实际展示内容。例如 ODP 目前是文本，PSD 依赖合成图，XMind 仅还原主要主题层级；不能只凭扩展名已注册就宣称完整兼容。

## 回归验证

相关测试覆盖快照、特殊字符路径、64 MiB 以上文件、Range、HEAD、访问边界、关闭回收、连续预览请求，以及各格式的解析与资源释放。

1.1.0 开发期间通过了 74 项 Flutter 测试、20 项宿主前端测试、100 项 Office-Viewer 测试，以及静态检查。实际本机会话地址上的浏览器检查覆盖 PPTX 图表与翻页、Parquet 分页与 206 请求、HEIC、CUR、PSD、XMind、Java、PDF 和大视频地址加载。

这些结果不等于所有操作系统上的完整 UI 验收。原生 WebView、媒体编码和系统菜单仍应在相应平台实测。上游能力核对记录保留在[仓库审计文档](https://github.com/w0fv1/VerTree/blob/main/docs/office-preview-upstream-audit.md)。
