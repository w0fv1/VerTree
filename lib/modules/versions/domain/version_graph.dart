import 'version_name.dart';

class VersionEntry {
  VersionEntry(this.path) : name = VersionName.parse(path);
  final String path;
  final VersionName name;
}

class VersionGraph {
  VersionGraph(List<VersionEntry> input) : entries = List.unmodifiable(input) {
    final links = <String, String>{};
    final warnings = <String>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entries.take(i).any((e) => e.name.version == entry.name.version)) {
        warnings.add('Duplicate version ${entry.name.version}: ${entry.path}');
        continue;
      }
      for (final candidate in entries.take(i)) {
        if (candidate.name.version.isChild(entry.name.version) ||
            candidate.name.version.isDirectBranch(entry.name.version)) {
          links[entry.path] = candidate.path;
          break;
        }
      }
      if (i > 0 && !links.containsKey(entry.path)) {
        warnings.add('Missing parent for ${entry.path}');
      }
    }
    parents = Map.unmodifiable(links);
    diagnostics = List.unmodifiable(warnings);
  }
  final List<VersionEntry> entries;
  late final Map<String, String> parents;
  late final List<String> diagnostics;
}
