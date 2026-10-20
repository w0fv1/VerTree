import 'dart:io';

enum ConversionState { queued, running, completed, failed, cancelled }

class ConversionFormat {
  const ConversionFormat({
    required this.id,
    required this.name,
    required this.extensions,
  });
  final String id;
  final String name;
  final List<String> extensions;

  String get description {
    const descriptions = {
      'jpg': '适合照片和网页图片，文件较小，不保留透明背景。',
      'png': '无损图片格式，支持透明背景，适合截图和图标。',
      'webp': '现代网页图片格式，体积小，支持透明和动画。',
      'avif': '高压缩率图片格式，适合需要更小体积的图片。',
      'gif': '适合简单动画和短循环图片，颜色数量有限。',
      'pdf': '适合打印、归档和跨设备分享，页面布局更稳定。',
      'mp4': '兼容性很好的视频格式，适合播放和分享。',
      'webm': '面向网页的视频格式，体积小，适合浏览器播放。',
      'mp3': '通用音频格式，体积小，适合播放和分享。',
      'wav': '无损音频格式，体积较大，适合后期编辑。',
      'flac': '无损压缩音频格式，适合保存高质量音乐。',
      'docx': '可编辑的 Word 文档格式。',
      'xlsx': '可编辑的 Excel 表格格式。',
      'pptx': '可编辑的 PowerPoint 演示文稿格式。',
      'txt': '纯文本格式，兼容性最好，不包含排版。',
      'html': '网页文档格式，可在浏览器中打开。',
      'zip': '通用压缩包格式，适合打包和传输多个文件。',
    };
    return descriptions[id.toLowerCase()] ?? 'Filee 支持的目标格式，可按需要选择。';
  }
}

class ConversionJob {
  ConversionJob({required this.sources, required this.target});
  final List<String> sources;
  final String target;
  ConversionState state = ConversionState.queued;
  double progress = 0;
  List<String> outputs = const [];
  String? error;
}

bool hasFileExtension(String path, String extension) {
  final value = path.toLowerCase();
  return value.endsWith('.${extension.toLowerCase().replaceFirst('.', '')}');
}

String fileNameWithoutExtension(String path) {
  final file = File(path).uri.pathSegments.last;
  final index = file.lastIndexOf('.');
  return index > 0 ? file.substring(0, index) : file;
}
