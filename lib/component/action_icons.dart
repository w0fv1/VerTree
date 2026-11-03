import 'package:flutter/material.dart';

enum AppActionIcon {
  preview(Icons.visibility_outlined),
  backup(Icons.save_outlined),
  expressBackup(Icons.bolt_outlined),
  monitor(Icons.monitor_heart_outlined),
  share(Icons.share_outlined),
  viewTree(Icons.account_tree_outlined),
  fileUsage(Icons.lock_open_outlined),
  fastDelete(Icons.delete_forever_outlined),
  conversion(Icons.transform_outlined),
  settings(Icons.settings_outlined),
  exit(Icons.logout_outlined);

  const AppActionIcon(this.data);
  final IconData data;

  String asset({String extension = 'png'}) =>
      'assets/img/icon/action-$name.$extension';
}
