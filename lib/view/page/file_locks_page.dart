import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../adapters/ui/desktop_scope.dart';
import '../../adapters/ui/file_tools_controller.dart';
import '../../component/i18n_lang.dart';
import '../../modules/file_locks/file_locks.dart';
import '../component/app_bar.dart';
import '../component/file_tool_widgets.dart';

class FileLocksPage extends StatelessWidget {
  const FileLocksPage({super.key, this.paths = const []});
  final List<String> paths;
  @override
  Widget build(BuildContext context) {
    final desktop = DesktopScope.read(context);
    String text(String zh, String en) =>
        desktop.appLocale.lang == Lang.en || desktop.appLocale.lang == Lang.ja
        ? en
        : zh;
    return Scaffold(
      appBar: VAppBar(title: Text(text('解除占用', 'File Locksmith'))),
      body: Platform.isWindows
          ? FileLocksPane(
              controller: desktop.fileTools,
              text: text,
              initialPaths: paths,
            )
          : Center(
              child: Text(
                text('此功能仅支持 Windows。', 'Available on Windows only.'),
              ),
            ),
    );
  }
}

/// Inspection and process actions only. This page never submits a deletion.
class FileLocksPane extends StatefulWidget {
  const FileLocksPane({
    super.key,
    required this.controller,
    required this.text,
    this.initialPaths = const [],
  });
  final FileToolsController controller;
  final FileToolText text;
  final List<String> initialPaths;
  @override
  State<FileLocksPane> createState() => _FileLocksPaneState();
}

class _FileLocksPaneState extends State<FileLocksPane> {
  late List<String> _paths;
  String? _message;
  bool _confirming = false;
  bool _ownsScan = false;
  bool _hasScan = false;
  FileToolsController get tools => widget.controller;
  FileToolText get t => widget.text;
  bool get _busy => tools.scanning || tools.acting || _confirming;

  @override
  void initState() {
    super.initState();
    _paths = List.of(
      widget.initialPaths.isNotEmpty ? widget.initialPaths : tools.usagePaths,
    );
    tools.addListener(_refresh);
    if (_paths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_scan());
      });
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _error(Object error) {
    if (mounted) setState(() => _message = '$error');
  }

  @override
  void dispose() {
    tools.removeListener(_refresh);
    if (_ownsScan && tools.scanning) tools.cancelScan();
    super.dispose();
  }

  void _select(List<String> paths) {
    if (!mounted || _busy) return;
    setState(() {
      _paths = paths;
      _message = null;
      _hasScan = false;
    });
    if (paths.isNotEmpty) unawaited(_scan());
  }

  Future<void> _scan({bool? elevated}) async {
    if (_paths.isEmpty || _busy) return;
    setState(() {
      _message = null;
      _hasScan = true;
      _ownsScan = true;
    });
    try {
      await tools.scan(
        List.of(_paths),
        elevated: elevated ?? tools.usageElevated,
      );
    } catch (error) {
      _error(error);
    } finally {
      _ownsScan = false;
    }
  }

  Future<void> _end(FileUsageProcess process) async {
    if (_busy || !process.actionAllowed) return;
    setState(() => _confirming = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t('结束任务？', 'End task?')),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${process.name}  ·  PID ${process.pid}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                SelectableText(process.imagePath),
                const SizedBox(height: 16),
                Text(
                  t(
                    '该程序中未保存的内容可能丢失。只结束此进程，不删除任何文件。',
                    'Unsaved work in this program may be lost. Only this process is ended; no files are deleted.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(t('结束任务', 'End task')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final outcomes = await tools.act(
        [process],
        FileProcessAction.terminate,
        confirmed: true,
      );
      if (!mounted) return;
      final outcome = outcomes.firstOrNull;
      if (outcome == null ||
          !['exited', 'alreadyExited'].contains(outcome['status'])) {
        _error(
          outcome?['error'] ??
              t(
                '进程尚未确认退出。',
                'The process has not been confirmed to have exited.',
              ),
        );
      }
      // Refresh after the action, without coupling this page to deletion/retry.
      await tools.scan(List.of(_paths), elevated: tools.usageElevated);
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Widget _width(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1080),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final processes = _hasScan && _paths.isNotEmpty
        ? tools.processes
        : const <FileUsageProcess>[];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _width(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('解除占用', 'File Locksmith'),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('refresh-usage'),
                        tooltip: t('刷新', 'Refresh'),
                        onPressed: _busy || _paths.isEmpty
                            ? null
                            : () => _scan(),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: const ValueKey('admin-scan'),
                        tooltip: t('以管理员权限重新扫描', 'Rescan as administrator'),
                        onPressed: _busy || _paths.isEmpty
                            ? null
                            : () => _scan(elevated: true),
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t(
                      '查看哪些程序正在使用文件，并结束对应任务。',
                      'Find programs using your files and end the corresponding tasks.',
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FileToolTargetPicker(
                    paths: _paths,
                    onChanged: _select,
                    onError: _error,
                    text: t,
                    enabled: !_busy,
                  ),
                  if (_message != null)
                    FileToolNotice(
                      message: _message!,
                      error: true,
                      onDismiss: () => setState(() => _message = null),
                    ),
                  if (_hasScan && _paths.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _paths.length == 1
                                ? p.windows.basename(_paths.single)
                                : t(
                                    '${_paths.length} 个项目',
                                    '${_paths.length} items',
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (tools.usageElevated)
                          Text(t('管理员', 'Administrator')),
                        if (tools.scanning || tools.acting)
                          TextButton(
                            onPressed: tools.acting
                                ? tools.cancelAction
                                : tools.cancelScan,
                            child: Text(t('停止', 'Stop')),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (tools.scanning || tools.acting) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        tools.acting
                            ? t('正在结束任务…', 'Ending task…')
                            : t('正在检查占用…', 'Checking file usage…'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!tools.scanning && tools.usage?.complete == false)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          t(
                            '部分进程无法检查。可使用右上角的管理员按钮重新扫描。',
                            'Some processes could not be inspected. Use the administrator button to rescan.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (!_busy && processes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            const Icon(Icons.lock_open_rounded, size: 40),
                            const SizedBox(height: 14),
                            Text(
                              t(
                                '未发现可访问的占用进程',
                                'No accessible using processes found',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: processes.length,
            itemBuilder: (_, index) {
              final process = processes[index];
              return _width(
                FileUsageProcessTile(
                  key: ValueKey('${process.pid}:${process.creationTime}'),
                  process: process,
                  text: t,
                  busy: _busy,
                  onEnd: () => _end(process),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
