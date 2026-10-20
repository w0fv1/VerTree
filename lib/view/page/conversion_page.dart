import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:vertree/modules/conversion/application/conversion_queue.dart';
import 'package:vertree/modules/conversion/domain/conversion_models.dart';
import 'package:vertree/modules/conversion/infrastructure/filee_runtime.dart';
import 'package:vertree/view/component/app_bar.dart';
import 'package:vertree/view/component/app_page_background.dart';
import 'package:vertree/view/module/file_preview_dialog.dart';

class ConversionPage extends StatefulWidget {
  const ConversionPage({super.key, this.initialFiles = const []});
  final List<String> initialFiles;
  @override
  State<ConversionPage> createState() => _ConversionPageState();
}

class _ConversionPageState extends State<ConversionPage> {
  late final ConversionQueue _queue;
  final List<String> _files = [];
  List<ConversionFormat> _targets = const [];
  StreamSubscription<ConversionJob>? _updates;
  String? _target;
  final TextEditingController _formatSearch = TextEditingController();
  bool _loading = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _queue = ConversionQueue(FileeRuntime());
    if (widget.initialFiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _setFiles(widget.initialFiles),
      );
    }
    _updates = _queue.updates.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _updates?.cancel();
    _formatSearch.dispose();
    _queue.dispose();
    super.dispose();
  }

  Future<void> _selectFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (result != null)
      await _setFiles(
        result.files.map((file) => file.path).whereType<String>(),
      );
  }

  Future<void> _setFiles(Iterable<String> files) async {
    final values = files.where((file) => file.isNotEmpty).toSet().toList();
    if (values.isEmpty) return;
    setState(() {
      _files
        ..clear()
        ..addAll(values);
      _targets = const [];
      _target = null;
      _loading = true;
    });
    try {
      final targets = await _queue.runtime.targetsFor(values.first);
      if (mounted)
        setState(() {
          _targets = targets;
          _target = targets.isEmpty ? null : targets.first.id;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _targets = const [];
          _target = null;
        });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ConversionFormat> get _visibleTargets {
    final query = _formatSearch.text.trim().toLowerCase();
    final source = _files.isEmpty
        ? ''
        : p.extension(_files.first).toLowerCase();
    final category = _formatCategory(source);
    return _targets.where((format) {
      final categoryMatch =
          category == null ||
          _formatCategory('.${format.id}') == null ||
          _formatCategory('.${format.id}') == category;
      final queryMatch =
          query.isEmpty ||
          format.id.contains(query) ||
          format.name.toLowerCase().contains(query) ||
          format.description.contains(query);
      return categoryMatch && queryMatch;
    }).toList();
  }

  String? _formatCategory(String extension) {
    final value = extension.toLowerCase();
    const groups = {
      'image': {
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'bmp',
        'tif',
        'tiff',
        'avif',
        'ico',
        'svg',
        'heic',
      },
      'video': {
        'mp4',
        'mov',
        'mkv',
        'webm',
        'avi',
        'wmv',
        'flv',
        'mpeg',
        'mpg',
        'ts',
        '3gp',
      },
      'audio': {'mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wma'},
      'document': {
        'pdf',
        'docx',
        'doc',
        'odt',
        'rtf',
        'txt',
        'md',
        'html',
        'epub',
      },
      'data': {'json', 'yaml', 'yml', 'xml', 'csv', 'tsv', 'toml'},
      'archive': {'zip', '7z', 'rar', 'tar', 'gz'},
    };
    final normalized = value.replaceFirst('.', '');
    for (final entry in groups.entries) {
      if (entry.value.contains(normalized)) return entry.key;
    }
    return null;
  }

  Future<void> _convert() async {
    final target = _target;
    if (target == null || _files.isEmpty) return;
    await _queue.enqueue(List.of(_files), target);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const VAppBar(title: Text('格式转换'), goHome: true),
      body: AppPageBackground(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: DropTarget(
                  onDragEntered: (_) => setState(() => _dragging = true),
                  onDragExited: (_) => setState(() => _dragging = false),
                  onDragDone: (detail) {
                    setState(() => _dragging = false);
                    _setFiles(detail.files.map((file) => file.path));
                  },
                  child: InkWell(
                    onTap: _selectFiles,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _dragging
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _dragging
                                  ? Icons.file_download_done_rounded
                                  : Icons.swap_horiz_rounded,
                              size: 54,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _files.isEmpty
                                  ? '拖放文件到这里，或点击选择'
                                  : '${_files.length} 个文件已选择',
                              style: theme.textTheme.titleMedium,
                            ),
                            if (_files.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                _files.map(p.basename).join('、'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_files.length == 1)
                                TextButton.icon(
                                  onPressed: () =>
                                      showFilePreview(context, _files.first),
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    size: 17,
                                  ),
                                  label: const Text('预览原文件'),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_loading) const LinearProgressIndicator(),
              if (_files.isNotEmpty) ...[
                TextField(
                  controller: _formatSearch,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '筛选目标格式',
                    hintText: '输入 jpg、图片、pdf…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue:
                      _visibleTargets.any((format) => format.id == _target)
                      ? _target
                      : null,
                  decoration: InputDecoration(
                    labelText: '转换为（${_visibleTargets.length} 种可用格式）',
                  ),
                  items: _visibleTargets
                      .map(
                        (format) => DropdownMenuItem(
                          value: format.id,
                          child: Tooltip(
                            message: format.description,
                            child: Text('${format.name} (.${format.id})'),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _target = value),
                ),
                if (_target != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _selectedTargetDescription,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _target == null ? null : _convert,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('开始转换'),
                ),
              ],
              if (_queue.history.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('转换记录', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                ..._queue.history
                    .take(4)
                    .map(
                      (job) => ListTile(
                        dense: true,
                        leading: Icon(_iconFor(job.state)),
                        title: Text(
                          '${job.sources.length} 个文件 → ${job.target.toUpperCase()}',
                        ),
                        subtitle: Text(
                          job.error ??
                              (job.state == ConversionState.completed
                                  ? '已完成'
                                  : '处理中'),
                        ),
                        trailing: job.outputs.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.visibility_outlined),
                                tooltip: '预览结果',
                                onPressed: () =>
                                    showFilePreview(context, job.outputs.first),
                              ),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(ConversionState state) => switch (state) {
    ConversionState.completed => Icons.check_circle_rounded,
    ConversionState.failed => Icons.error_rounded,
    ConversionState.running => Icons.sync_rounded,
    _ => Icons.schedule_rounded,
  };

  String get _selectedTargetDescription {
    for (final format in _visibleTargets) {
      if (format.id == _target) return format.description;
    }
    return '';
  }
}
