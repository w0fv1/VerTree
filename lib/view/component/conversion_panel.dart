import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:vertree/modules/conversion/conversion.dart';

import 'conversion_format_picker.dart';
import 'file_details.dart';
import 'file_result_tile.dart';

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
  ConversionFormat? _target;
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
      _target = null;
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
      setState(() => _target = target);
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

  Future<void> _convert() async {
    final target = _target;
    if (_busy || target == null || _files.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _queue.enqueue(_files, target.id);
    } finally {
      if (mounted) setState(() => _busy = false);
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
        Tooltip(
          message: '选择文件',
          child: InkWell(
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_files.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(Icons.upload_file_outlined, size: 36),
                          SizedBox(height: 10),
                          Text('拖放文件到这里，或点击选择'),
                        ],
                      ),
                    ),
                  for (final file in _files)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.topRight,
                            child: FileDetails(
                              path: file,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(
                                Icons.insert_drive_file_outlined,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  p.basename(file),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: '预览源文件',
                                  icon: const Icon(Icons.visibility_outlined),
                                  onPressed: () => widget.onPreview(file),
                                ),
                                if (file == _files.last)
                                  IconButton(
                                    tooltip: '清空选择',
                                    icon: const Icon(Icons.clear_all),
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() {
                                            _files = const [];
                                            _target = null;
                                            _error = null;
                                          }),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_target != null) Text(_target!.id.toUpperCase()),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '选择格式',
                onPressed: _busy ? null : () => _chooseFormat(_files),
                icon: const Icon(Icons.tune),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: '转换',
                onPressed: _busy || _target == null ? null : _convert,
                icon: const Icon(Icons.transform_outlined),
              ),
            ],
          ),
        for (final job in _queue.history) ...[
          for (final output in job.outputs)
            FileResultTile(
              key: ValueKey(output),
              path: output,
              onPreview: widget.onPreview,
            ),
          if (job.state != ConversionState.completed)
            ListTile(
              leading: Icon(
                job.state == ConversionState.failed
                    ? Icons.error_outline
                    : Icons.sync,
              ),
              title: Text(job.sources.map(p.basename).join('、')),
              subtitle: Text(job.error ?? '处理中'),
            ),
        ],
      ],
    ),
  );
}
