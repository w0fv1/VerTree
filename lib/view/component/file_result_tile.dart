import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pasteboard/pasteboard.dart';
import 'package:vertree/component/file_utils.dart';

import 'file_details.dart';

class FileResultTile extends StatelessWidget {
  const FileResultTile({
    super.key,
    required this.path,
    required this.onPreview,
  });
  final String path;
  final ValueChanged<String> onPreview;

  Future<void> _act(
    BuildContext context,
    Future<void> Function() action, {
    String? success,
  }) async {
    try {
      await action();
      if (context.mounted && success != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.task_alt),
    title: Text(p.basename(path), maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: FileDetails(path: path),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '预览结果',
          icon: const Icon(Icons.visibility_outlined),
          onPressed: () => onPreview(path),
        ),
        IconButton(
          tooltip: '复制文件',
          icon: const Icon(Icons.copy_outlined),
          onPressed: () => _act(context, () async {
            if (!await Pasteboard.writeFiles([path])) {
              throw StateError('无法复制文件');
            }
          }, success: '已复制文件'),
        ),
        IconButton(
          tooltip: '在文件资源管理器中打开',
          icon: const Icon(Icons.folder_open_outlined),
          onPressed: () => _act(context, () => FileUtils.revealFile(path)),
        ),
      ],
    ),
  );
}
