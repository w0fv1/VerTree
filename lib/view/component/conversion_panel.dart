import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:vertree/modules/conversion/conversion.dart';

import 'conversion_format_picker.dart';

class ConversionPanel extends StatefulWidget {
  const ConversionPanel({
    super.key,
    required this.createQueue,
    required this.onPreview,
    this.initialFiles = const [],
  });
  final ConversionQueue Function() createQueue;
  final ValueChanged<String> onPreview;
  final List<String> initialFiles;
  @override
  State<ConversionPanel> createState() => _ConversionPanelState();
}

class _ConversionPanelState extends State<ConversionPanel> {
  late final ConversionQueue _queue;
  StreamSubscription<ConversionJob>? _updates;
  List<String> _files = const [];
  bool _busy = false;
  bool _loading = false;
  bool _dragging = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _queue = widget.createQueue();
    _updates = _queue.updates.listen((_) {
      if (mounted) setState(() {});
    });
    if (widget.initialFiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _chooseFormat(widget.initialFiles),
      );
    }
  }

  @override
  void dispose() {
    _updates?.cancel();
    _queue.dispose();
    super.dispose();
  }

  Future<void> _selectFiles() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (!mounted || result == null) return;
    await _chooseFormat(
      result.files.map((file) => file.path).whereType<String>().toList(),
    );
  }

  Future<void> _chooseFormat(List<String> paths) async {
    final files = paths.where((path) => path.isNotEmpty).toSet().toList();
    if (!mounted || _busy || files.isEmpty) return;
    setState(() {
      _files = files;
      _error = null;
      _busy = true;
      _loading = true;
    });
    try {
      final capabilities = await Future.wait(
        files.map(_queue.runtime.targetsFor),
      );
      if (!mounted) return;
      setState(() => _loading = false);
      final targets = capabilities.first
          .where(
            (format) => capabilities.every(
              (list) => list.any((item) => item.id == format.id),
            ),
          )
          .toList();
      if (targets.isEmpty) {
        setState(
          () =>
              _error = files.length == 1 ? '这个文件没有可用的转换格式' : '这些文件没有共同可用的转换格式',
        );
        return;
      }
      final target = await showDialog<ConversionFormat>(
        context: context,
        builder: (_) => ConversionFormatPicker(formats: targets),
      );
      if (!mounted || target == null) return;
      await _queue.enqueue(files, target.id);
    } catch (error) {
      if (mounted) setState(() => _error = '转换失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => DropTarget(
    onDragEntered: (_) => setState(() => _dragging = true),
    onDragExited: (_) => setState(() => _dragging = false),
    onDragDone: (details) =>
        _chooseFormat(details.files.map((file) => file.path).toList()),
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        InkWell(
          onTap: _busy ? null : _selectFiles,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: _dragging
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Column(
              children: [
                const Icon(Icons.transform_outlined, size: 36),
                const SizedBox(height: 10),
                Text(
                  _files.isEmpty
                      ? '拖放文件到这里，或点击选择'
                      : _files.map(p.basename).join('、'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_loading ||
            _queue.history.any((job) => job.state == ConversionState.running))
          const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_files.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _chooseFormat(_files),
                icon: const Icon(Icons.transform_outlined),
                label: const Text('选择格式'),
              ),
              if (_files.length == 1)
                TextButton.icon(
                  onPressed: () => widget.onPreview(_files.first),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('预览原文件'),
                ),
            ],
          ),
        for (final job in _queue.history)
          ListTile(
            leading: Icon(switch (job.state) {
              ConversionState.completed => Icons.check_circle_outline,
              ConversionState.failed => Icons.error_outline,
              _ => Icons.sync,
            }),
            title: Text(
              '${job.sources.length} 个文件 → ${job.target.toUpperCase()}',
            ),
            subtitle: Text(
              job.error ??
                  (job.state == ConversionState.completed ? '已完成' : '处理中'),
            ),
            trailing: job.outputs.isEmpty
                ? null
                : IconButton(
                    tooltip: '预览结果',
                    icon: const Icon(Icons.visibility_outlined),
                    onPressed: () => widget.onPreview(job.outputs.first),
                  ),
          ),
      ],
    ),
  );
}
