class FileChange {
  const FileChange(this.path, this.type);
  final String path;
  final int type;
}

abstract interface class FileWatcher {
  Stream<FileChange> watch(String path);
}
