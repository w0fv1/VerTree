# 上游预览能力核对

核对日期：2026-09-07。Vertree 直接依赖我们自己的 Office-Viewer；该仓库参考的功能上游是 [cweijan/vscode-office](https://github.com/cweijan/vscode-office)。本次核对其 main 提交 `908258dafc827ce0475fe7671d414914fbd3867b`，同时读取格式注册和具体实现，未直接替换现有子模块。

## 尚未接入的格式

| 格式 | 上游实现 | 接入注意事项 |
| --- | --- | --- |
| HEIC / HEIF | `src/react/view/image/convertImage.ts`，heic2any 转 JPEG | 需要引入解码库并验证离线 Worker/CSP；不能只增加扩展名 |
| Parquet | `src/react/view/parquet/parquetParser.ts`，hyparquet | 可复用列式数据解析并显示表格；大文件应分页或限制预览行数 |
| CRX | `src/provider/archiveViewerProvider.ts` 路由到 ZIP 处理器 | 需用 CRX2/CRX3 实际样例验证包装头，提供压缩条目预览 |
| CUR | `src/provider/handlers/imageHanlder.ts` 按图标加载 | 浏览器支持需实测，必要时转换为 PNG |
| PJP / PJPEG | 同一图片处理器，按 JPEG 加载 | JPEG 扩展名别名，可复用现有图片入口 |
| Java .class | `src/provider/javaDecompilerProvider.ts` | 上游调用 Java 运行随包提供的反编译 JAR，需要原生进程桥接和 Java 运行环境，不能只移植 React |

[固定版本格式注册与依赖清单](https://github.com/cweijan/vscode-office/blob/908258dafc827ce0475fe7671d414914fbd3867b/package.json)。本表列的是发现的缺口，本次取消大小限制没有把这些格式标记为已支持。

## 已有入口，但上游显示更完整

| 格式 | 当前 Office-Viewer / Vertree | 上游实现 |
| --- | --- | --- |
| PPTX | 逐页文本和备注 | `src/react/view/powerpoint/PowerPoint.tsx` 使用 pptxviewjs 显示幻灯片 |
| PSD | 尺寸、图层结构摘要 | `src/react/view/psd/psdParser.ts` 读取合成图和图层图像，可显示画面 |
| XMind | 文本和结构摘要 | `src/react/view/xmind/XmindViewer.tsx` 使用 Mind Elixir 与 XMind 导入器显示思维导图 |
| DOCX | Mammoth 转正文 HTML | 上游使用 docx-editor-react，版式能力不同，应以复杂文档样例比较 |

这些改进比只增加扩展名更影响预览体验。建议优先补齐 PPTX、PSD、XMind 的可视化，再接入 HEIC/HEIF、Parquet 和图片别名、CRX；Java 反编译单独处理其运行环境需求。

未发现旧 DOC/PPT、MSG、MOBI/AZW 的专用预览入口，不能认为更新这个上游就能直接支持它们。HTTP/REST 请求发送、Git 历史和编辑功能不属于本次只读文件预览范围。
