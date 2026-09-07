import 'dart:io';
import 'package:path/path.dart' as p;
import '../ports/file_watcher.dart';

class LocalFileWatcher implements FileWatcher {
  @override
  Stream<FileChange> watch(String path) => File(path).parent
      .watch()
      .where((event) => p.equals(p.normalize(event.path), p.normalize(path)))
      .map((event) => FileChange(event.path, event.type));
}
