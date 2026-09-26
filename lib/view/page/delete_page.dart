import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../adapters/ui/desktop_scope.dart';
import '../../adapters/ui/file_tools_controller.dart';
import '../../component/i18n_lang.dart';
import '../../modules/deletion/deletion.dart';
import '../component/app_bar.dart';
import '../component/file_tool_widgets.dart';

class DeletePage extends StatelessWidget {
  const DeletePage({
    super.key,
    this.paths = const [],
    this.confirmOnOpen = false,
  });
  final List<String> paths;
  final bool confirmOnOpen;
  @override
  Widget build(BuildContext context) {
    final desktop = DesktopScope.read(context);
    String text(String zh, String en) =>
        desktop.appLocale.lang == Lang.en || desktop.appLocale.lang == Lang.ja
        ? en
        : zh;
    return Scaffold(
      appBar: VAppBar(title: Text(text('删除', 'Delete'))),
      body: Platform.isWindows
          ? DeletePane(
              controller: desktop.fileTools,
              text: text,
              initialPaths: paths,
              confirmOnOpen: confirmOnOpen,
            )
          : Center(
              child: Text(
                text('此功能仅支持 Windows。', 'Available on Windows only.'),
              ),
            ),
    );
  }
}

/// One selection, one confirmation, one current operation. No history dashboard.
class DeletePane extends StatefulWidget {
  const DeletePane({
    super.key,
    required this.controller,
    required this.text,
    this.initialPaths = const [],
    this.confirmOnOpen = false,
  });
  final FileToolsController controller;
  final FileToolText text;
  final List<String> initialPaths;
  final bool confirmOnOpen;
  @override
  State<DeletePane> createState() => _DeletePaneState();
}

class _DeletePaneState extends State<DeletePane> {
  late List<String> _paths;
  DeletionTaskView? _current;
  String? _message;
  bool _confirming = false;
  FileToolsController get tools => widget.controller;
  FileToolText get t => widget.text;
  bool get _running => _current != null && !_current!.job.completed;
  bool get _busy => _running || _confirming || tools.preparing;

  @override
  void initState() {
    super.initState();
    _paths = List.of(widget.initialPaths);
    _current = tools.tasks.where((task) => !task.job.completed).firstOrNull;
    if (_current != null) _paths = _current!.plan.paths;
    tools.addListener(_refresh);
    if (widget.confirmOnOpen && _paths.isNotEmpty && !_running) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_delete());
      });
    }
  }

  @override
  void dispose() {
    tools.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _error(Object error) {
    if (mounted) setState(() => _message = '$error');
  }

  void _select(List<String> paths) {
    if (!mounted || _busy) return;
    setState(() {
      _paths = paths;
      _current = null;
      _message = null;
    });
  }

  Future<void> _delete() async {
    if (_paths.isEmpty || _busy) return;
    setState(() {
      _confirming = true;
      _message = null;
    });
    try {
      final previous = _current;
      final retry =
          previous?.result?.outcome == 'partial' &&
          previous?.result?.reportPath != null;
      final plan = retry
          ? previous!.plan
          : await tools.prepare(List.of(_paths));
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(t('确认删除？', 'Delete these items?'))),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(
                    '永久删除，不进入回收站。',
                    'Permanently delete, without using the Recycle Bin.',
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  t(
                    '会自动清除只读属性，并结束可处理的占用程序。程序中未保存的内容可能丢失；已删除内容不能撤销。',
                    'Read-only attributes will be cleared and actionable programs using blocked files may be ended. Unsaved work may be lost. Completed deletions cannot be undone.',
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: plan.targets.length,
                    itemBuilder: (_, index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: SelectableText(plan.targets[index].path),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  retry
                      ? t(
                          '只重试上次未删除且身份未变化的项目。',
                          'Retry only unchanged items left by the previous attempt.',
                        )
                      : t(
                          '包含所选文件夹内的子项；不会进入链接指向的位置。',
                          'Includes folder contents; link destinations are not traversed.',
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  t(
                    '系统保护或无法解除的阻碍将保留并报告。',
                    'Protected or unresolved items will be preserved and reported.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
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
            FilledButton.icon(
              key: const ValueKey('confirm-delete'),
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.bolt_rounded, size: 19),
              label: Text(t('删除', 'Delete')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final entry = tools.start(
        plan,
        const DeletionOptions.lightning(),
        confirmed: true,
        retryReport: retry ? previous!.result!.reportPath : null,
      );
      if (mounted) setState(() => _current = entry);
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  String _status(DeletionTaskView task) {
    if (!task.job.completed && task.job.cancelRequested) {
      return t('正在停止…', 'Stopping…');
    }
    if (!task.job.completed) {
      return switch (task.progress.data['phase']) {
        'resolving' => t('正在查找删除阻碍…', 'Finding deletion blockers…'),
        'releasing' => t('正在解除文件占用…', 'Releasing file usage…'),
        'retrying' => t('正在删除剩余项目…', 'Deleting remaining items…'),
        _ => t('正在删除…', 'Deleting…'),
      };
    }
    return switch (task.job.status) {
      'succeeded' => t('删除完成', 'Deletion complete'),
      'partial' => t('部分项目未能删除', 'Some items could not be deleted'),
      'cancelled' => t(
        '已停止，已删除内容不能撤销',
        'Stopped; completed deletions cannot be undone',
      ),
      'interrupted' => t(
        '操作中断，剩余项目未自动续删',
        'Interrupted; remaining items were not automatically resumed',
      ),
      _ => t('删除失败', 'Deletion failed'),
    };
  }

  Widget _progress(DeletionTaskView task) {
    final result = task.result;
    final progress = result?.progress ?? task.progress;
    final failures = result?.failures ?? const <Map<String, dynamic>>[];
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                task.job.status == 'succeeded'
                    ? Icons.check_circle_outline
                    : Icons.bolt_rounded,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _status(task),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (!task.job.completed)
                TextButton(
                  onPressed: task.job.cancelRequested
                      ? null
                      : () => tools.cancel(task),
                  child: Text(t('停止', 'Stop')),
                ),
            ],
          ),
          if (!task.job.completed) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress.percent),
          ],
          const SizedBox(height: 12),
          Text(
            t(
              '已删除 ${progress.filesDeleted} 个文件、${progress.directoriesDeleted} 个文件夹',
              'Deleted ${progress.filesDeleted} files and ${progress.directoriesDeleted} folders',
            ),
          ),
          if (progress.failures > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t(
                  '未完成 ${progress.failures} 项',
                  '${progress.failures} items remain',
                ),
              ),
            ),
          if (progress.data['processesEnded'] case final num count
              when count > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t('已结束 $count 个占用进程', 'Ended $count using processes'),
              ),
            ),
          if (result?.message?.isNotEmpty == true || task.job.error != null)
            FileToolNotice(
              message: result?.message ?? task.job.error!,
              error: true,
            ),
          if (failures.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(t('查看未删除的项目', 'View remaining items')),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: failures.length,
                    itemBuilder: (_, index) {
                      final error = failures[index];
                      final target = error['target'] as Map?;
                      return ListTile(
                        title: SelectableText('${target?['path'] ?? ''}'),
                        subtitle: SelectableText(
                          '${error['code']}: ${error['message']}',
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('删除', 'Delete'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  '自动处理占用与只读，快速永久删除。',
                  'Resolve file usage and read-only attributes, then permanently delete.',
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
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const ValueKey('delete-selection'),
                  onPressed: _busy || _paths.isEmpty ? null : _delete,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 18,
                    ),
                  ),
                  icon: const Icon(Icons.bolt_rounded),
                  label: Text(t('删除', 'Delete')),
                ),
              ),
              if (_confirming && tools.preparing) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(t('正在验证所选目标…', 'Validating the selected items…')),
              ],
              if (_message != null)
                FileToolNotice(
                  message: _message!,
                  error: true,
                  onDismiss: () => setState(() => _message = null),
                ),
              if (_current != null) _progress(_current!),
            ],
          ),
        ),
      ),
    );
  }
}
