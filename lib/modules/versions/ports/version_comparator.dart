abstract interface class VersionComparator {
  Future<VersionComparison> compare(String leftPath, String rightPath);
}

class VersionComparison {
  const VersionComparison({
    required this.leftPath,
    required this.rightPath,
    required this.leftSha256,
    required this.rightSha256,
    this.changes,
  });
  final String leftPath, rightPath, leftSha256, rightSha256;
  final List<TextChange>? changes;
  bool get equal => leftSha256 == rightSha256;
}

class TextChange {
  const TextChange(this.operation, this.text);
  final String operation, text;
}
