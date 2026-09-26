import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Baseline only. The caller must pass this runner's freshly created benchmark
/// fixture marker; arbitrary recursive deletion is deliberately not exposed.
Future<void> main(List<String> args) async {
  if (args.length != 2) throw ArgumentError('Expected temporary dataset and fixture marker');
  final target = p.normalize(p.absolute(args[0]));
  final marker = File(p.normalize(p.absolute(args[1])));
  final root = p.dirname(marker.path);
  if (p.basename(target) != 'dataset' || p.dirname(target) != root ||
      p.basename(marker.path) != '.vertree-test-fixture' ||
      !p.basename(root).startsWith('VerTree-FileTools-Benchmark-') ||
      !p.isWithin(p.normalize(Directory.systemTemp.path), root) ||
      await marker.readAsString() != 'benchmark fixture' ||
      await FileSystemEntity.type(target, followLinks: false) != FileSystemEntityType.directory) {
    throw StateError('Refusing a non-benchmark directory');
  }
  final watch = Stopwatch()..start();
  await Directory(target).delete(recursive: true);
  watch.stop();
  stdout.writeln(jsonEncode({'engineSeconds': watch.elapsedMicroseconds / 1000000,
    'mode': 'Dart Directory.delete(recursive: true)'}));
}
