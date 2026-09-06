# Vertree 1.1.0

新增本地文件预览：在 Windows 文件右键菜单选择“预览文件”，或从版本树节点打开预览，即可查看文件内容。也支持命令行 `vertree preview <path>`。

## 文件预览

- 集成 Office Viewer，只读预览办公文档、PDF、图片、文本、音视频、电子书、邮件和压缩包，文件内容在本机处理。
- 扩展 Office 模板、宏文档及 OpenDocument 格式，增加 EPUB、FB2、CBZ、EML、HEIC/HEIF、AVIF、CUR、SVGZ、Parquet、CRX 和 Java class 等格式支持。
- PPTX 幻灯片支持画布显示和翻页；PSD 显示保存的合成图及图层信息；XMind 支持可缩放、可折叠的思维导图。
- 取消固定的 64 MiB 文件大小上限。音视频、PDF 和 Parquet 支持按需分段读取，其他格式仍受解析器、可用内存和临时磁盘空间限制。
- 未知格式仅检测是否为文本；可识别则显示文本，否则提示不支持。移除十六进制和无意义的回退信息。

## 操作与界面

- 简化 Windows 右键菜单注册逻辑，统一管理预览、备份、监控和版本树入口。
- 连续预览多个文件时自动关闭上一个预览窗口，修复弹窗叠加。
- 去掉重复文件名和多余状态文字，“用系统程序打开”改为图标按钮。
- 去掉版本树画布的外层边框和包边。

## 下载与使用

- Windows 常规安装下载 `vertree-windows-x64-1.1.0-setup.exe`，免安装使用下载 `.zip`；另提供 MSI、MSIX 和调试工件。
- macOS 提供带架构标识的 ZIP、DMG；Linux 提供 TAR.GZ、DEB、RPM。
- Windows 预览需要 WebView2 Runtime；macOS 使用嵌入式 WebView，Linux 使用本机浏览器打开预览。
- 预览不保证完整还原所有排版；旧版 DOC/PPT、MSG、MOBI/AZW 和加密文档暂不支持，音视频解码取决于系统浏览器能力。

Office-Viewer 的配套改进已同步提交至 [Office-Viewer 仓库](https://github.com/w0fv1/Office-Viewer)，Vertree 固定使用提交 `9b7f8ec`。
