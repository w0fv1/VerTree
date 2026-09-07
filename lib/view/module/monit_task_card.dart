import 'package:flutter/material.dart';
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/modules/monitoring/monitoring.dart';
import 'package:vertree/component/file_utils.dart';
import 'package:vertree/component/notifier.dart';
import 'package:vertree/component/themed_assets.dart';
import 'package:vertree/adapters/ui/desktop_scope.dart';

class MonitTaskCard extends StatefulWidget {
  final FileMonitTask task;
  final Function(FileMonitTask task) removeTask;

  const MonitTaskCard({
    super.key,
    required this.task,
    required this.removeTask,
  });

  @override
  State<MonitTaskCard> createState() => _MonitTaskCardState();
}

class _MonitTaskCardState extends State<MonitTaskCard> {
  late final DesktopDependencies _desktop;
  @override
  void initState() {
    super.initState();
    _desktop = DesktopScope.read(context);
  }

  late FileMonitTask task = widget.task;

  Future<void> _toggleTask() async {
    final result = await _desktop.monitService.toggleFileMonitTaskStatus(task);
    if (!mounted) return;
    result.when(
      ok: (updatedTask) {
        setState(() {
          task = updatedTask;
        });
        final status = updatedTask.enabled
            ? _desktop.appLocale.getText(LocaleKey.monitcardStatusEnabled)
            : _desktop.appLocale.getText(LocaleKey.monitcardStatusDisabled);
        showToast(
          _desktop.appLocale.getText(LocaleKey.monitcardMonitorStatus).tr([
            task.filePath,
            status,
          ]),
        );
      },
      err: (_, msg) {
        showToast(msg);
        setState(() {});
      },
    );
  }

  void _openBackupFolder() {
    if (task.backupDirPath != null) {
      FileUtils.openFolder(task.backupDirPath!);
    }
  }

  void _cleanBackupFolder() {
    if (task.backupDirPath != null) {
      showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              _desktop.appLocale.getText(LocaleKey.monitcardCleanDialogTitle),
            ),
            content: Text(
              _desktop.appLocale
                  .getText(LocaleKey.monitcardCleanDialogContent)
                  .tr([task.backupDirPath!]),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(
                  _desktop.appLocale.getText(
                    LocaleKey.monitcardCleanDialogCancel,
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              TextButton(
                child: Text(
                  _desktop.appLocale.getText(
                    LocaleKey.monitcardCleanDialogConfirm,
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      ).then((confirmed) async {
        if (confirmed != null && confirmed) {
          try {
            await _desktop.monitService.clearSnapshots(task);
            showToast(
              _desktop.appLocale.getText(LocaleKey.monitcardCleanSuccess).tr([
                task.backupDirPath!,
              ]),
            );
          } catch (e) {
            showToast(
              _desktop.appLocale.getText(LocaleKey.monitcardCleanFail).tr([
                task.backupDirPath!,
                e.toString(),
              ]),
            );
            _desktop.logger.error('删除备份文件夹中的文件时发生错误: $e');
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final running = task.runtimeStatus == 'running';
    final degraded = task.runtimeStatus == 'degraded';
    final statusColor = degraded
        ? scheme.error
        : running
        ? Colors.green.shade700
        : scheme.outline;

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: Card.outlined(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.circle, color: statusColor, size: 12),
                  const SizedBox(width: 8),
                  Text(
                    degraded
                        ? _desktop.appLocale.getText(
                            LocaleKey.monitcardStatusDegraded,
                          )
                        : running
                        ? _desktop.appLocale.getText(
                            LocaleKey.monitcardStatusRunning,
                          )
                        : _desktop.appLocale.getText(
                            LocaleKey.monitcardStatusStopped,
                          ),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: _desktop.appLocale.getText(
                      LocaleKey.monitcardPause,
                    ),
                    child: Switch(
                      value: task.enabled,
                      onChanged: (_) => _toggleTask(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                task.filePath,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              if (task.backupDirPath != null)
                Text(
                  _desktop.appLocale
                      .getText(LocaleKey.monitcardBackupFolder)
                      .tr([task.backupDirPath!]),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  Tooltip(
                    message: _desktop.appLocale.getText(
                      LocaleKey.fileleafMenuShare,
                    ),
                    child: IconButton.filledTonal(
                      onPressed: () =>
                          _desktop.openLanShareDialogForPath(task.filePath),
                      icon: shareActionImage(size: 20),
                    ),
                  ),
                  Tooltip(
                    message: _desktop.appLocale.getText(
                      LocaleKey.monitcardOpenBackupFolder,
                    ),
                    child: IconButton.filledTonal(
                      onPressed: _openBackupFolder,
                      icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    ),
                  ),
                  Tooltip(
                    message: _desktop.appLocale.getText(
                      LocaleKey.monitcardClean,
                    ),
                    child: IconButton.filledTonal(
                      onPressed: _cleanBackupFolder,
                      icon: const Icon(
                        Icons.cleaning_services_rounded,
                        size: 20,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: _desktop.appLocale.getText(
                      LocaleKey.monitcardDelete,
                    ),
                    child: IconButton.filled(
                      onPressed: () {
                        widget.removeTask(task);
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
