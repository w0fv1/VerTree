import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/core/monit_manager.dart';
import 'package:vertree/component/file_utils.dart';
import 'package:vertree/component/notifier.dart';
import 'package:vertree/component/themed_assets.dart';
import 'package:vertree/main.dart';

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
  late FileMonitTask task = widget.task;

  Future<void> _toggleTask() async {
    final result = await monitService.toggleFileMonitTaskStatus(task);
    result.when(
      ok: (updatedTask) {
        setState(() {
          task = updatedTask;
        });
        final status = updatedTask.isRunning
            ? appLocale.getText(LocaleKey.monitcardStatusEnabled)
            : appLocale.getText(LocaleKey.monitcardStatusDisabled);
        showToast(
          appLocale.getText(LocaleKey.monitcardMonitorStatus).tr([
            task.file.path,
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
            title: Text(appLocale.getText(LocaleKey.monitcardCleanDialogTitle)),
            content: Text(
              appLocale.getText(LocaleKey.monitcardCleanDialogContent).tr([
                task.backupDirPath!,
              ]),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(
                  appLocale.getText(LocaleKey.monitcardCleanDialogCancel),
                ),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              TextButton(
                child: Text(
                  appLocale.getText(LocaleKey.monitcardCleanDialogConfirm),
                ),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      ).then((confirmed) {
        if (confirmed != null && confirmed) {
          try {
            final directory = Directory(task.backupDirPath!);
            final files = directory.listSync();

            for (final file in files) {
              if (file is File) {
                file.deleteSync();
              }
            }
            showToast(
              appLocale.getText(LocaleKey.monitcardCleanSuccess).tr([
                task.backupDirPath!,
              ]),
            );
          } catch (e) {
            showToast(
              appLocale.getText(LocaleKey.monitcardCleanFail).tr([
                task.backupDirPath!,
                e.toString(),
              ]),
            );
            logger.error('删除备份文件夹中的文件时发生错误: $e');
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = task.isRunning ? Colors.green.shade700 : scheme.outline;

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
                    task.isRunning
                        ? appLocale.getText(LocaleKey.monitcardStatusRunning)
                        : appLocale.getText(LocaleKey.monitcardStatusStopped),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: appLocale.getText(LocaleKey.monitcardPause),
                    child: Switch(
                      value: task.isRunning,
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
                  appLocale.getText(LocaleKey.monitcardBackupFolder).tr([
                    task.backupDirPath!,
                  ]),
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
                    message: appLocale.getText(LocaleKey.fileleafMenuShare),
                    child: IconButton.filledTonal(
                      onPressed: () => openLanShareDialogForPath(task.filePath),
                      icon: shareActionImage(size: 20),
                    ),
                  ),
                  Tooltip(
                    message: appLocale.getText(
                      LocaleKey.monitcardOpenBackupFolder,
                    ),
                    child: IconButton.filledTonal(
                      onPressed: _openBackupFolder,
                      icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    ),
                  ),
                  Tooltip(
                    message: appLocale.getText(LocaleKey.monitcardClean),
                    child: IconButton.filledTonal(
                      onPressed: _cleanBackupFolder,
                      icon: const Icon(
                        Icons.cleaning_services_rounded,
                        size: 20,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: appLocale.getText(LocaleKey.monitcardDelete),
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
