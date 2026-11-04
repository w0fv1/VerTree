import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FileDetails extends StatefulWidget {
  const FileDetails({super.key, required this.path, this.textAlign});
  final String path;
  final TextAlign? textAlign;

  @override
  State<FileDetails> createState() => _FileDetailsState();
}

class _FileDetailsState extends State<FileDetails> {
  late Future<FileStat> _stat;

  @override
  void initState() {
    super.initState();
    _stat = FileStat.stat(widget.path);
  }

  @override
  void didUpdateWidget(FileDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _stat = FileStat.stat(widget.path);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FileStat>(
    future: _stat,
    builder: (context, snapshot) {
      final stat = snapshot.data;
      if (stat == null) return const SizedBox.shrink();
      if (stat.type == FileSystemEntityType.notFound) {
        return Text('文件不存在', style: Theme.of(context).textTheme.bodySmall);
      }
      var size = stat.size.toDouble();
      const units = ['B', 'KB', 'MB', 'GB', 'TB'];
      var unit = 0;
      while (size >= 1024 && unit < units.length - 1) {
        size /= 1024;
        unit++;
      }
      final date = Platform.isWindows ? stat.changed : stat.modified;
      final label = Platform.isWindows ? '创建' : '修改';
      return Text(
        '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]} · $label ${DateFormat('yyyy-MM-dd HH:mm').format(date)}',
        textAlign: widget.textAlign,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    },
  );
}
