import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:vertree/component/I18nLang.dart';
import 'package:vertree/core/MonitManager.dart';
import 'package:vertree/component/Notifier.dart';
import 'package:vertree/component/ThemedAssets.dart';
import 'package:vertree/main.dart';
import 'package:vertree/view/component/AppBar.dart';
import 'package:vertree/view/component/AppPageBackground.dart';
import 'package:vertree/view/module/MonitTaskCard.dart';

class MonitPage extends StatefulWidget {
  const MonitPage({super.key});

  @override
  State<MonitPage> createState() => _MonitPageState();
}

class _MonitPageState extends State<MonitPage> {
  // Original list of all tasks
  List<FileMonitTask> _allMonitTasks = [];

  // List of tasks currently displayed (filtered)
  List<FileMonitTask> _filteredMonitTasks = [];

  // Controller for the search text field
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    // Load initial tasks
    _allMonitTasks = List.from(monitService.monitFileTasks); // Make a copy
    _filteredMonitTasks = List.from(_allMonitTasks); // Initially show all
    sortTasks();

    super.initState();

    // Listen to search input changes
    _searchController.addListener(_onSearchChanged);
  }

  void sortTasks() {
    _filteredMonitTasks.sort((a, b) {
      if (a.isRunning && !b.isRunning) {
        return -1; // a is running, b is not, so a comes first
      } else if (!a.isRunning && b.isRunning) {
        return 1; // b is running, a is not, so b comes first
      } else {
        return 0; // Both have the same running status, maintain original order (or sort by another criteria if needed)
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  // Called when search text changes
  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _filterTasks();
    });
  }

  // Filters the tasks based on the search query
  void _filterTasks() {
    if (_searchQuery.isEmpty) {
      // If search is empty, show all tasks
      _filteredMonitTasks = List.from(_allMonitTasks);
    } else {
      // Otherwise, filter by filePath containing the query (case-insensitive)
      _filteredMonitTasks = _allMonitTasks
          .where(
            (task) => task.filePath.toLowerCase().contains(
              _searchQuery.toLowerCase(),
            ),
          )
          .toList();
    }
    // No need to call setState here as it's called within _onSearchChanged
    // or after add/remove operations that also call setState.
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
            // Add to the original list
            _allMonitTasks.add(task);
            // Re-apply the filter to update the displayed list
            _filterTasks();
            sortTasks();
          });
          if (mounted) {
            showToast(
              appLocale.getText(LocaleKey.monit_addSuccess).tr([task.filePath]),
            );
          }
        },
        err: (error, msg) {
          if (mounted) {
            showToast(appLocale.getText(LocaleKey.monit_addFail).tr([msg]));
          }
        },
      );
    } else {
      if (mounted) {
        showToast(appLocale.getText(LocaleKey.monit_fileNotSelected));
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
          title: Text(appLocale.getText(LocaleKey.monit_deleteDialogTitle)),
          content: Text(
            appLocale.getText(LocaleKey.monit_deleteDialogContent).tr([
              task.filePath,
            ]),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(appLocale.getText(LocaleKey.monit_cancel)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(appLocale.getText(LocaleKey.monit_delete)),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      await monitService.removeFileMonitTask(task.filePath);
      setState(() {
        // Remove from the original list
        _allMonitTasks.removeWhere((t) => t.filePath == task.filePath);
        // Re-apply the filter to update the displayed list
        _filterTasks();
      });
      showToast(
        appLocale.getText(LocaleKey.monit_deleteSuccess).tr([task.filePath]),
      );
      // Safely delete directory if it exists
      try {
        final backupDir = Directory(task.backupDirPath!);
        if (await backupDir.exists()) {
          await backupDir.delete(recursive: true);
        }
      } catch (e) {
        // Handle potential errors during deletion (e.g., permissions)
        logger.error(
          "Error deleting backup directory ${task.backupDirPath}: $e",
        );
        // Optionally show a message to the user
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
            LocaleKey.monit_cleanInvalidTaskDialogNoInvalidTasks,
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
            appLocale.getText(LocaleKey.monit_cleanInvalidTasksDialogTitle),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: invalidTasks.map((task) {
                return Text(
                  appLocale.getText(LocaleKey.monit_invalidTaskDialogItem).tr([
                    task.filePath,
                    task.backupDirPath ??
                        appLocale.getText(
                          LocaleKey.monit_cleanInvalidTaskDialogBackupDirNotSet,
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
              child: Text(appLocale.getText(LocaleKey.monit_cancel)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(appLocale.getText(LocaleKey.monit_delete)),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      for (var task in invalidTasks) {
        await monitService.removeFileMonitTask(task.filePath);
        // Safely delete directory if it exists
        try {
          final backupDir = Directory(task.backupDirPath!);
          if (await backupDir.exists()) {
            await backupDir.delete(recursive: true);
          }
        } catch (e) {
          // Handle potential errors during deletion (e.g., permissions)
          logger.error(
            "Error deleting backup directory ${task.backupDirPath}: $e",
          );
          // Optionally show a message to the user
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
          appLocale.getText(LocaleKey.monit_cleanInvalidTaskDialogCleaned),
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
            Text(appLocale.getText(LocaleKey.monit_title)),
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
                  hintText: appLocale.getText(LocaleKey.monit_searchHint),
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
                                ? appLocale.getText(LocaleKey.monit_empty)
                                : appLocale.getText(LocaleKey.monit_noResults),
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
              tooltip: appLocale.getText(LocaleKey.monit_cleanInvalidAction),
              onPressed: _cleanInvalidTask,
              child: const Icon(Icons.cleaning_services_rounded, size: 18),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.small(
              heroTag: 'share_file',
              tooltip: appLocale.getText(LocaleKey.fileleaf_menuShare),
              onPressed: _shareFile,
              child: shareActionImage(size: 18),
            ),
            const SizedBox(height: 10),
          ],
          FloatingActionButton.extended(
            heroTag: 'add_monitor_task',
            tooltip: appLocale.getText(LocaleKey.monit_addTaskAction),
            onPressed: _addNewTask,
            icon: const Icon(Icons.add),
            label: Text(appLocale.getText(LocaleKey.monit_addTaskAction)),
          ),
        ],
      ),
    );
  }
}
