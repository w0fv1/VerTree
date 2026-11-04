import 'package:flutter/material.dart';
import 'package:vertree/adapters/ui/desktop_scope.dart';
import 'package:vertree/view/component/app_bar.dart';
import 'package:vertree/view/component/app_page_background.dart';
import 'package:vertree/view/component/conversion_panel.dart';
import 'package:vertree/view/module/file_preview_dialog.dart';

class ConversionPage extends StatelessWidget {
  const ConversionPage({super.key, this.initialFiles = const []});
  final List<String> initialFiles;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const VAppBar(title: Text('格式转换'), goHome: true),
    body: AppPageBackground(
      child: ConversionPanel(
        createQueue: DesktopScope.read(context).createConversionQueue,
        initialFiles: initialFiles,
        onPreview: (path) => showFilePreview(context, path),
      ),
    ),
  );
}
