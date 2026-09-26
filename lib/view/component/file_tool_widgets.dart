import '../../platform/windows_file_tools_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../modules/file_locks/file_locks.dart';

typedef FileToolText = String Function(String chinese, String english);

/// Picker-only selection shared by the two independent pages. Paths are labels,
/// never editable text. The selection contains only explicitly picked roots.
class FileToolTargetPicker extends StatefulWidget {
  const FileToolTargetPicker({
    super.key,
    required this.paths,
    required this.onChanged,
    required this.onError,
    required this.text,
    this.enabled = true,
  });
  final List<String> paths;
  final ValueChanged<List<String>> onChanged;
  final ValueChanged<Object> onError;
  final FileToolText text;
  final bool enabled;
  @override
  State<FileToolTargetPicker> createState() => _FileToolTargetPickerState();
}

class _FileToolTargetPickerState extends State<FileToolTargetPicker> {
  bool _picking = false;
  bool get enabled => widget.enabled && !_picking;

  Future<void> _pick() async {
    if (!enabled) return;
    setState(() => _picking = true);
    try {
      final values = await WindowsFileToolsPicker.pick(
        title: widget.text('选择文件或文件夹', 'Choose files or folders'),
        selectLabel: widget.text('选择选中项', 'Choose selected items'),
        folderLabel: widget.text('选择此文件夹', 'Choose this folder'),
        hint: widget.text(
          '可同时选择文件和文件夹；双击文件夹进入。',
          'Select files and folders together; double-click a folder to browse.',
        ),
        initialDirectory: widget.paths.isEmpty
            ? null
            : p.windows.dirname(widget.paths.first),
      );
      if (!mounted || !widget.enabled || values == null) return;
      final next = {...widget.paths, ...values}.toList();
      if (next.length > 1024) {
        widget.onError(
          widget.text(
            '一次最多选择 1024 个文件或文件夹。',
            'Select up to 1,024 files or folders.',
          ),
        );
      } else if (values.isNotEmpty) {
        widget.onChanged(next);
      }
    } catch (error) {
      if (mounted) widget.onError(error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final paths = widget.paths;
    final text = widget.text;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('pick-targets-card'),
        onTap: enabled ? _pick : null,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.folder_open_outlined,
                    color: colors.primary,
                    size: 26,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      paths.isEmpty
                          ? text(
                              '点击选择文件或文件夹',
                              'Click to choose files or folders',
                            )
                          : text('点击添加文件或文件夹', 'Click to add files or folders'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (paths.isNotEmpty)
                    IconButton(
                      key: const ValueKey('clear-targets'),
                      tooltip: text('清空选择', 'Clear selection'),
                      onPressed: enabled ? () => widget.onChanged([]) : null,
                      icon: const Icon(Icons.clear_all_rounded),
                    ),
                ],
              ),
              if (paths.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 26),
                  child: Text(
                    text(
                      '支持多选文件和文件夹',
                      'Files and folders can be selected together',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              if (paths.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: paths.length,
                    itemBuilder: (context, index) => ListTile(
                      contentPadding: const EdgeInsets.only(left: 4),
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(
                        p.windows.basename(paths[index]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        paths[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: text('移除选择', 'Remove selection'),
                        onPressed: enabled
                            ? () =>
                                  widget.onChanged([...paths]..removeAt(index))
                            : null,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ),
                  ),
                ),
              ],
              if (_picking) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

class FileToolNotice extends StatelessWidget {
  const FileToolNotice({
    super.key,
    required this.message,
    this.onDismiss,
    this.error = false,
  });
  final String message;
  final VoidCallback? onDismiss;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? colors.errorContainer : colors.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(error ? Icons.error_outline : Icons.info_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(message)),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
            ),
        ],
      ),
    );
  }
}

/// File Locksmith-style process card: icon/name, one End task action, expander.
/// Details stay collapsed until requested; no checkbox/bulk-action toolbar.
class FileUsageProcessTile extends StatefulWidget {
  const FileUsageProcessTile({
    super.key,
    required this.process,
    required this.onEnd,
    required this.text,
    this.busy = false,
  });
  final FileUsageProcess process;
  final VoidCallback onEnd;
  final FileToolText text;
  final bool busy;
  @override
  State<FileUsageProcessTile> createState() => _FileUsageProcessTileState();
}

class _FileUsageProcessTileState extends State<FileUsageProcessTile> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final process = widget.process;
    final text = widget.text;
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Icon(
                  Icons.web_asset_outlined,
                  color: colors.onSurfaceVariant,
                  size: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    process.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  key: ValueKey('end-process-${process.pid}'),
                  onPressed: widget.busy || !process.actionAllowed
                      ? null
                      : widget.onEnd,
                  icon: const Icon(Icons.block_outlined, size: 18),
                  label: Text(text('结束任务', 'End task')),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: text(
                    _expanded ? '收起详情' : '展开详情',
                    _expanded ? 'Hide details' : 'Show details',
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: colors.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText('PID  ${process.pid}'),
                  const SizedBox(height: 8),
                  SelectableText('${text('用户', 'User')}  ${process.user}'),
                  const SizedBox(height: 8),
                  SelectableText(
                    '${text('程序路径', 'Application path')}\n${process.imagePath}',
                  ),
                  if (!process.actionAllowed)
                    FileToolNotice(
                      message:
                          '${text('此进程不可结束', 'This process cannot be ended')}: ${process.restriction}',
                    ),
                  const SizedBox(height: 16),
                  Text(
                    text('正在使用的文件', 'Files in use'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: process.files.length,
                      itemBuilder: (_, index) {
                        final file = process.files[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: SelectableText(
                            '${file['path']}\n${(file['sources'] as List? ?? []).join(', ')}',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
