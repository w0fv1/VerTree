import 'package:flutter/services.dart';

/// Native, read-only selection. The returned names are validated by the existing
/// deletion/usage commands; picking never grants deletion authorization.
class WindowsFileToolsPicker {
  static const channel = MethodChannel('vertree/file-tools-picker');
  static Future<List<String>?> pick({
    required String title,
    required String selectLabel,
    required String folderLabel,
    required String hint,
    String? initialDirectory,
  }) => channel.invokeListMethod<String>('pickItems', {
    'title': title,
    'selectLabel': selectLabel,
    'folderLabel': folderLabel,
    'hint': hint,
    'initialDirectory': initialDirectory,
  });
}
