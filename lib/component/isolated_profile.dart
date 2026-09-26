import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:path/path.dart' as p;

/// Opt-in local smoke-test profile. It must be an existing ordinary directory
/// under the OS temp directory. It never alters normal settings or startup menus.
String? get isolatedProfilePath {
  final value = Platform.environment['VERTREE_ISOLATED_PROFILE'];
  if (value == null || value.isEmpty) return null;
  final path = p.normalize(p.absolute(value));
  final directory = Directory(path);
  if (!p.isWithin(p.normalize(Directory.systemTemp.path), path) ||
      !p.basename(path).startsWith('VerTree-Smoke-') ||
      FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.directory ||
      !p.equals(p.normalize(directory.resolveSymbolicLinksSync()), path)) {
    throw StateError(
      'VERTREE_ISOLATED_PROFILE must be an existing VerTree-Smoke-* directory under the OS temp directory',
    );
  }
  return path;
}

String get isolatedInstanceSuffix {
  final path = isolatedProfilePath;
  return path == null
      ? ''
      : '.smoke.${sha256.convert(utf8.encode(path.toLowerCase())).toString().substring(0, 16)}';
}
