import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../domain/conversion_models.dart';
import '../ports/conversion_runtime.dart';

class FileeRuntime implements ConversionRuntime {
  FileeRuntime({String? executable})
    : _executable = executable ?? _resolveExecutable();
  final String _executable;
  static String _resolveExecutable() {
    final rid = Platform.isWindows
        ? 'win-x64'
        : Platform.isMacOS
        ? (Platform.version.contains('arm64') ? 'osx-arm64' : 'osx-x64')
        : 'linux-x64';
    final exe = Platform.isWindows ? 'filee-cli.exe' : 'filee-cli';
    final candidates = [
      p.join(Directory.current.path, 'vendor', 'filee', rid, exe),
      p.join(
        File(Platform.resolvedExecutable).parent.path,
        'vendor',
        'filee',
        rid,
        exe,
      ),
      p.join(
        File(Platform.resolvedExecutable).parent.path,
        '..',
        'Resources',
        'vendor',
        'filee',
        rid,
        exe,
      ),
      p.join(File(Platform.resolvedExecutable).parent.path, exe),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return candidates.first;
  }

  Future<ProcessResult> _run(List<String> args) =>
      Process.run(_executable, args, runInShell: false);

  @override
  Future<List<ConversionFormat>> formats() async {
    final result = await _run(['formats']);
    if (result.exitCode != 0) throw StateError('${result.stderr}'.trim());
    final formats = <ConversionFormat>[];
    final linePattern = RegExp(
      r'^\s{2}([a-z0-9][a-z0-9_-]*)\s{2,}(.+?)\s{2,}((?:\.\S+\s*)+)$',
    );
    for (final line in const LineSplitter().convert('${result.stdout}')) {
      final match = linePattern.firstMatch(line);
      if (match == null || line.contains('(read only)')) continue;
      final id = match.group(1)!;
      final name = match.group(2)!.trim();
      final extensions = RegExp(r'\.([a-z0-9]+)', caseSensitive: false)
          .allMatches(match.group(3)!)
          .map((match) => match.group(1)!.toLowerCase())
          .toList();
      formats.add(ConversionFormat(id: id, name: name, extensions: extensions));
    }
    return formats;
  }

  @override
  Future<List<ConversionFormat>> targetsFor(String source) async {
    final ext = p.extension(source).replaceFirst('.', '');
    final result = await _run(['formats', ext]);
    if (result.exitCode != 0) return const [];
    final text = '${result.stdout}';
    final section = text.contains('converts to:')
        ? text.split('converts to:').last
        : '';
    final ids = RegExp(
      r'\b[a-z][a-z0-9_-]*\b',
    ).allMatches(section).map((m) => m.group(0)!).toSet();
    return (await formats())
        .where((format) => ids.contains(format.id) && format.id != ext)
        .toList();
  }

  @override
  Future<ConversionResult> convert(
    ConversionJob job, {
    void Function(double)? onProgress,
  }) async {
    job.state = ConversionState.running;
    onProgress?.call(0.1);
    final args = ['convert', ...job.sources, '--to', job.target, '--json'];
    final result = await _run(args);
    onProgress?.call(1);
    if (result.exitCode != 0 && result.exitCode != 1) {
      return ConversionResult(
        error: '${result.stderr}'.trim().isEmpty
            ? 'Filee conversion failed'
            : '${result.stderr}'.trim(),
      );
    }
    try {
      final json = jsonDecode('${result.stdout}') as Map<String, dynamic>;
      final outputs = [
        for (final file in (json['files'] as List<dynamic>? ?? const []))
          ...(file as Map<String, dynamic>)['outputs'] as List<dynamic>? ??
              const [],
      ].cast<String>();
      final failed = (json['failed'] as num?)?.toInt() ?? 0;
      return failed == 0
          ? ConversionResult(outputs: outputs)
          : ConversionResult(
              outputs: outputs,
              error: 'Some files could not be converted',
            );
    } catch (_) {
      return ConversionResult(
        error: '${result.stderr}'.trim().isEmpty
            ? 'Invalid Filee result'
            : '${result.stderr}'.trim(),
      );
    }
  }
}
