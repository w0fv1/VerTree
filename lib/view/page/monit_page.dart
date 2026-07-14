import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/core/monit_manager.dart';
import 'package:vertree/component/notifier.dart';
import 'package:vertree/component/themed_assets.dart';
import 'package:vertree/main.dart';
import 'package:vertree/view/component/app_bar.dart';
import 'package:vertree/view/component/app_page_background.dart';
import 'package:vertree/view/module/monit_task_card.dart';

class MonitPage extends StatefulWidget {
  const MonitPage({super.key});

  @override
  State<MonitPage> createState() => _MonitPageState();
}

class _MonitPageState extends State<MonitPage> {
  List<FileMonitTask> _allMonitTasks = [];

  List<FileMonitTask> _filteredMonitTasks = [];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    _allMonitTasks = List.from(monitService.monitFileTasks);
    _filteredMonitTasks = List.from(_allMonitTasks);
    sortTasks();

    super.initState();

    _searchController.addListener(_onSearchChanged);
  }

  void sortTasks() {
    _filteredMonitTasks.sort((a, b) {
      if (a.isRunning && !b.isRunning) {
        return -1;
      } else if (!a.isRunning && b.isRunning) {
        return 1;
      } else {
        return 0;
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _filterTasks();
    });
  }

  void _filterTasks() {
    if (_searchQuery.isEmpty) {
      _filteredMonitTasks = List.from(_allMonitTasks);
    } else {
      _filteredMonitTasks = _allMonitTasks
          .where(
            (task) => task.filePath.toLowerCase().contains(
              _searchQuery.toLowerCase(),
            ),
          )
          .toList();
    }
  }

  Future<void> _addNewTask() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null && result.files.single.path != null) {
      String selectedFilePath = result.files.single.path!;

      final taskResult = await monitService.addFileMonitTask(selectedFilePath);
      taskResult.when(
        ok: (task) {
          setState(() {
            _allMonitTasks.add(task);

            _filterTasks();
            sortTasks();
          });
          if (mounted) {
            showToast(
              appLocale.getText(LocaleKey.monitAddSuccess).tr([task.filePath]),
            );
          }
        },
        err: (error, msg) {
          if (mounted) {
            showToast(appLocale.getText(LocaleKey.monitAddFail).tr([msg]));
          }
        },
      );
    } else {
      if (mounted) {
        showToast(appLocale.getText(LocaleKey.monitFileNotSelected));
      }
    }
  }

  Future<void> _shareFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final selectedFilePath = result?.files.single.path;
    if (selectedFilePath == null || selectedFilePath.isEmpty) {
      return;
    }
    await openLanShareDialogForPath(selectedFilePath);
  }

  Future<void> _removeTask(FileMonitTask task) async {
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(appLocale.getText(LocaleKey.monitDeleteDialogTitle)),
          content: Text(
            appLocale.getText(LocaleKey.monitDeleteDialogContent).tr([
              task.filePath,
            ]),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(appLocale.getText(LocaleKey.monitCancel)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(appLocale.getText(LocaleKey.monitDelete)),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      await monitService.removeFileMonitTask(task.filePath);
      setState(() {
        _allMonitTasks.removeWhere((t) => t.filePath == task.filePath);

        _filterTasks();
      });
      showToast(
        appLocale.getText(LocaleKey.monitDeleteSuccess).tr([task.filePath]),
      );

      try {
        final backupDir = Directory(task.backupDirPath!);
        if (await backupDir.exists()) {
          await backupDir.delete(recursive: true);
        }
      } catch (e) {
        logger.error(
          "Error deleting backup directory ${task.backupDirPath}: $e",
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error deleting backup: ${e.toString()}")),
          );
        }
      }
    }
  }

  Future<void> _cleanInvalidTask() async {
    List<FileMonitTask> invalidTasks = [];
    for (var task in _allMonitTasks) {
      if (!File(task.filePath).existsSync() ||
          (task.backupDirPath != null &&
              !Directory(task.backupDirPath!).existsSync())) {
        invalidTasks.add(task);
      }
    }

    if (invalidTasks.isEmpty) {
      if (mounted) {
        showToast(
          appLocale.getText(
            LocaleKey.monitCleanInvalidTaskDialogNoInvalidTasks,
          ),
        );
      }
      return;
    }

    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            appLocale.getText(LocaleKey.monitCleanInvalidTasksDialogTitle),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: invalidTasks.map((task) {
                return Text(
                  appLocale.getText(LocaleKey.monitInvalidTaskDialogItem).tr([
                    task.filePath,
                    task.backupDirPath ??
                        appLocale.getText(
                          LocaleKey.monitCleanInvalidTaskDialogBackupDirNotSet,
                        ),
                  ]),
                );
              }).toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(appLocale.getText(LocaleKey.monitCancel)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(appLocale.getText(LocaleKey.monitDelete)),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      for (var task in invalidTasks) {
        await monitService.removeFileMonitTask(task.filePath);

        try {
          final backupDir = Directory(task.backupDirPath!);
          if (await backupDir.exists()) {
            await backupDir.delete(recursive: true);
          }
        } catch (e) {
          logger.error(
            "Error deleting backup directory ${task.backupDirPath}: $e",
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Error deleting backup: ${e.toString()}")),
            );
          }
        }
      }

      setState(() {
        _allMonitTasks.removeWhere((task) => invalidTasks.contains(task));
        _filterTasks();
      });

      if (mounted) {
        showToast(
          appLocale.getText(LocaleKey.monitCleanInvalidTaskDialogCleaned),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: VAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monitor_heart_rounded, size: 18),
            const SizedBox(width: 8),
            Text(appLocale.getText(LocaleKey.monitTitle)),
          ],
        ),
      ),
      body: AppPageBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              child: MouseRegion(
                cursor: SystemMouseCursors.text,
                child: SearchBar(
                  controller: _searchController,
                  hintText: appLocale.getText(LocaleKey.monitSearchHint),
                  leading: const Icon(Icons.search_rounded),
                  trailing: [
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                        },
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _filteredMonitTasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _searchQuery.isEmpty
                                ? Icons.monitor_heart_outlined
                                : Icons.search_off_rounded,
                            size: 42,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isEmpty
                                ? appLocale.getText(LocaleKey.monitEmpty)
                                : appLocale.getText(LocaleKey.monitNoResults),
                            style: theme.textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 4, bottom: 92),
                      itemCount: _filteredMonitTasks.length,
                      itemBuilder: (context, index) {
                        final task = _filteredMonitTasks[index];
                        return MonitTaskCard(
                          task: task,
                          removeTask: _removeTask,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_allMonitTasks.isNotEmpty) ...[
            FloatingActionButton.small(
              heroTag: 'clean_invalid_tasks',
              tooltip: appLocale.getText(LocaleKey.monitCleanInvalidAction),
              onPressed: _cleanInvalidTask,
              child: const Icon(Icons.cleaning_services_rounded, size: 18),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.small(
              heroTag: 'share_file',
              tooltip: appLocale.getText(LocaleKey.fileleafMenuShare),
              onPressed: _shareFile,
              child: shareActionImage(size: 18),
            ),
            const SizedBox(height: 10),
          ],
          FloatingActionButton.extended(
            heroTag: 'add_monitor_task',
            tooltip: appLocale.getText(LocaleKey.monitAddTaskAction),
            onPressed: _addNewTask,
            icon: const Icon(Icons.add),
            label: Text(appLocale.getText(LocaleKey.monitAddTaskAction)),
          ),
        ],
      ),
    );
  }
}
