# 上游预览能力核对

核对日期：2026-09-07。Vertree 直接依赖我们自己的 Office-Viewer；该仓库参考的功能上游是 [cweijan/vscode-office](https://github.com/cweijan/vscode-office)。本次核对其 main 提交 `908258dafc827ce0475fe7671d414914fbd3867b`，同时读取格式注册和具体实现，未直接替换现有子模块。

## 核对时发现的格式缺口

| 格式 | 上游实现 | 接入注意事项 |
| --- | --- | --- |
| HEIC / HEIF | `src/react/view/image/convertImage.ts`，heic2any 转 JPEG | 需要引入解码库并验证离线 Worker/CSP；不能只增加扩展名 |
| Parquet | `src/react/view/parquet/parquetParser.ts`，hyparquet | 可复用列式数据解析并显示表格；大文件应分页或限制预览行数 |
| CRX | `src/provider/archiveViewerProvider.ts` 路由到 ZIP 处理器 | 需用 CRX2/CRX3 实际样例验证包装头，提供压缩条目预览 |
| CUR | `src/provider/handlers/imageHanlder.ts` 按图标加载 | 浏览器支持需实测，必要时转换为 PNG |
| PJP / PJPEG | 同一图片处理器，按 JPEG 加载 | JPEG 扩展名别名，可复用现有图片入口 |
| Java .class | `src/provider/javaDecompilerProvider.ts` | 上游调用 Java 运行随包提供的反编译 JAR，需要原生进程桥接和 Java 运行环境，不能只移植 React |

[固定版本格式注册与依赖清单](https://github.com/cweijan/vscode-office/blob/908258dafc827ce0475fe7671d414914fbd3867b/package.json)。本表记录取消大小限制时发现的缺口；后续接入状态见下节。

## 核对时已有入口，但上游显示更完整

| 格式 | 当前 Office-Viewer / Vertree | 上游实现 |
| --- | --- | --- |
| PPTX | 逐页文本和备注 | `src/react/view/powerpoint/PowerPoint.tsx` 使用 pptxviewjs 显示幻灯片 |
| PSD | 尺寸、图层结构摘要 | `src/react/view/psd/psdParser.ts` 读取合成图和图层图像，可显示画面 |
| XMind | 文本和结构摘要 | `src/react/view/xmind/XmindViewer.tsx` 使用 Mind Elixir 与 XMind 导入器显示思维导图 |
| DOCX | Mammoth 转正文 HTML | 上游使用 docx-editor-react，版式能力不同，应以复杂文档样例比较 |

这些改进比只增加扩展名更影响预览体验。DOCX 仍使用 Mammoth，本轮未替换为编辑器。

未发现旧 DOC/PPT、MSG、MOBI/AZW 的专用预览入口，不能认为更新这个上游就能直接支持它们。HTTP/REST 请求发送、Git 历史和编辑功能不属于本次只读文件预览范围。

## 后续接入结果

以上八个扩展名均已注册并接入专用预览，PPTX、PSD、XMind 的可视化也已完成。HEIC/HEIF 使用支持严格 CSP 的 heic-to；Java 改用 @run-slicer/vf 在 Worker 内反编译，无需本机 Java。Parquet 复用宿主 Range 服务，每页 100 行。

PPTX 的复杂动画和原版版式、PSD 无合成图文件、XMind 图片/附件/原始样式仍有边界，详见 [集成说明](office-preview.md)。第三方许可与源码地址随两个应用的前端资源打包。
