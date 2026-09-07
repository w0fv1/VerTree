import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    await CBuilder.library(
      name: 'vertree_file_access',
      assetName: 'file_access/infrastructure/publish_file.dart',
      sources: ['native/file_access.c'],
    ).run(input: input, output: output);
  });
}
