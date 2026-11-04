import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/conversion_models.dart';
import '../ports/conversion_runtime.dart';
import 'filee_format_output.dart';

class FileeRuntime implements ConversionRuntime {
  FileeRuntime({String? executable})
    : _executable = executable ?? _resolveExecutable();
  final String _executable;
  Future<List<ConversionFormat>>? _formatsCache;
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
    final cached = _formatsCache;
    if (cached != null) return cached;
    final future = _loadFormats();
    _formatsCache = future;
    return future;
  }

  Future<List<ConversionFormat>> _loadFormats() async {
    final result = await _run(['formats']);
    if (result.exitCode != 0) throw StateError('${result.stderr}'.trim());
    return FileeFormatOutput.formats('${result.stdout}');
  }

  @override
  Future<List<ConversionFormat>> targetsFor(String source) async {
    final ext = p.extension(source).replaceFirst('.', '').toLowerCase();
    final result = await _run(['formats', ext]);
    if (result.exitCode != 0) return const [];
    return FileeFormatOutput.targets('${result.stdout}', await formats(), ext);
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
