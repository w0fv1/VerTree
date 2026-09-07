import 'package:path/path.dart' as p;
import '../../../foundation/operation_failure.dart';
import 'version_number.dart';

class VersionName {
  const VersionName(this.name, this.extension, this.version, this.label);
  final String name, extension;
  final FileVersion version;
  final String? label;
  static final _suffix = RegExp(r'^(.*)\.((?:\d+\.\d+)(?:-\d+\.\d+)*)$');

  factory VersionName.parse(String path) {
    final basename = p.basenameWithoutExtension(path);
    final match = _suffix.firstMatch(basename);
    final base = match?.group(1) ?? basename;
    final hash = base.indexOf('#');
    return VersionName(
      hash < 0 ? base : base.substring(0, hash),
      p.extension(path).replaceFirst('.', ''),
      FileVersion(match?.group(2) ?? '0.0'),
      hash < 0 || hash == base.length - 1 ? null : base.substring(hash + 1),
    );
  }

  bool get supported =>
      name.isNotEmpty && !name.startsWith('.') && extension.isNotEmpty;
  bool sameFamily(VersionName other) =>
      name == other.name && extension == other.extension;
  String fileName(FileVersion number, String? label) =>
      '$name${label == null || label.isEmpty ? '' : '#$label'}.$number.$extension';

  static void validateLabel(String? label) {
    if (label != null &&
        (label.length > 120 ||
            RegExp(r'[<>:"/\\|?*#\x00-\x1f]').hasMatch(label) ||
            label.endsWith('.') ||
            label.endsWith(' '))) {
      throw const OperationFailure('INVALID_LABEL', 'Invalid version label');
    }
  }
}
