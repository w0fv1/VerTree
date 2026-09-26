import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:vertree/modules/settings/settings.dart';

/// The sole settings authority is settings.json. No legacy import or recovery
/// configuration is read. Reads are side-effect free; writes are queued and
/// staged beside the destination before replacement.
class Configer {
  Configer({
    Future<Directory> Function()? directoryResolver,
    void Function(String)? onLogError,
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory,
       _onLogError = onLogError;
  final Future<Directory> Function() _directoryResolver;
  final void Function(String)? _onLogError;
  late String configFilePath;
  Map<String, dynamic> _config = {};
  Future<void> _pendingSave = Future.value();
  Object? _saveError;
  bool _initialized = false;
  final _changes = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get changes => _changes.stream;

  Future<void> init() async {
    if (_initialized) return;
    final directory = await _directoryResolver();
    await directory.create(recursive: true);
    configFilePath = '${directory.path}/settings.json';
    final file = File(configFilePath);
    if (await file.exists()) {
      try {
        _config = _decode(await file.readAsString());
      } catch (error) {
        _onLogError?.call('Cannot read settings: $error');
        // Invalid/unsupported settings start from code defaults, never from a
        // previous file or the legacy schema. The next explicit write replaces
        // the invalid file using the same single-file commit path.
        _config = {};
      }
    }
    // Only obsolete settings filenames owned by this adapter are removed.
    // Never touch monitoring snapshots, application logs or unrelated files.
    for (final name in ['config.json', 'settings.json.previous']) {
      final obsolete = '${directory.path}/$name';
      try {
        if (await FileSystemEntity.type(obsolete, followLinks: false) ==
            FileSystemEntityType.file) {
          await File(obsolete).delete();
        }
      } catch (error) {
        _onLogError?.call('Cannot remove obsolete settings file $name: $error');
      }
    }
    _initialized = true;
  }

  Map<String, dynamic> _decode(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Settings must be an object');
    }
    final schema = decoded['_schemaVersion'];
    if (schema != 1) throw const FormatException('Unsupported settings schema');
    return decoded;
  }

  T get<T>(String key, T defaultValue) {
    final fallback = AppSettings.defaults[key] is T
        ? AppSettings.defaults[key] as T
        : defaultValue;
    final value = _config[key];
    if (value == null) return fallback;
    if (value is! T) return fallback;
    try {
      AppSettings.validate(key, value);
    } catch (_) {
      return fallback;
    }
    if (value is List || value is Map) {
      return jsonDecode(jsonEncode(value)) as T;
    }
    return value;
  }

  T set<T>(String key, T value) {
    if (!_initialized) {
      throw StateError('Settings must be initialized before writing');
    }
    AppSettings.validate(key, value);
    _config[key] = jsonDecode(jsonEncode(value));
    _config['_schemaVersion'] = 1;
    final snapshot = toJson();
    _pendingSave = _pendingSave.then((_) async {
      try {
        await _writeConfig(snapshot);
        _saveError = null;
      } catch (error) {
        _saveError = error;
        _onLogError?.call('Cannot save settings: $error');
      }
    });
    _changes.add(snapshot);
    return value;
  }

  Future<void> flush() async {
    await _pendingSave;
    if (_saveError != null) throw _saveError!;
  }

  Future<void> _writeConfig(Map<String, dynamic> snapshot) async {
    final file = File(configFilePath);
    final staged = File('$configFilePath.tmp');
    try {
      await staged.writeAsString(
        const JsonEncoder.withIndent('  ').convert(snapshot),
        flush: true,
      );
      await staged.rename(file.path);
    } finally {
      // The staging file is not a second configuration and is never read at
      // startup. Clean it after a failed commit without masking the write error.
      try {
        if (await staged.exists()) await staged.delete();
      } catch (error) {
        _onLogError?.call('Cannot remove settings staging file: $error');
      }
    }
  }

  Map<String, dynamic> toJson() =>
      jsonDecode(jsonEncode(_config)) as Map<String, dynamic>;
  Future<void> dispose() async {
    await flush();
    await _changes.close();
  }
}
