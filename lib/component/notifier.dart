import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:toastification/toastification.dart';
import 'package:vertree/component/file_utils.dart';
import 'dart:developer' as developer;

Future<void> initLocalNotifier() async {
  await localNotifier.setup(
    appName: 'Vertree',
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );
}

Future<void> showWindowsNotification(String title, String description) async {
  LocalNotification notification = LocalNotification(
    title: title,
    body: description,
  );

  notification.onShow = () {
    developer.log('通知已显示: ${notification.identifier}');
  };

  notification.onClose = (closeReason) {
    developer.log('通知已关闭: ${notification.identifier} - 关闭原因: $closeReason');
  };

  notification.onClick = () {
    developer.log('用户点击了通知: ${notification.identifier}');
  };

  await notification.show();
}

Future<void> showWindowsNotificationWithFile(
  String title,
  String description,
  String filePath,
) async {
  LocalNotification notification = LocalNotification(
    title: title,
    body: description,
  );

  notification.onClick = () {
    developer.log('用户点击了通知: ${notification.identifier}');
    FileUtils.openFile(filePath);
  };

  await notification.show();
}

Future<void> showWindowsNotificationWithFolder(
  String title,
  String description,
  String folderPath,
) async {
  LocalNotification notification = LocalNotification(
    title: title,
    body: description,
  );

  notification.onClick = () {
    developer.log('用户点击了通知: ${notification.identifier}');
    FileUtils.openFolder(folderPath);
  };

  await notification.show();
}

Future<void> showWindowsNotificationWithTask(
  String title,
  String description,
  FutureOr<void> Function() task,
) async {
  LocalNotification notification = LocalNotification(
    title: title,
    body: description,
  );

  notification.onClick = () {
    developer.log('用户点击了通知: ${notification.identifier}');
    unawaited(Future<void>.sync(task));
  };

  await notification.show();
}

void showToast(String message) {
  toastification.show(
    title: Text(message),
    autoCloseDuration: const Duration(seconds: 3),
    style: ToastificationStyle.simple,
    showProgressBar: false,
    alignment: Alignment.bottomCenter,
  );
}
