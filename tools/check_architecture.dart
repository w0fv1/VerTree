import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

/// Parse all directives, including exports, parts, and conditional imports.
/// Edges use repository-relative forward-slash paths for portable diagnostics.
Set<String> violations(Map<String, String> sources) {
  final result = <String>{};
  final moduleEdges = <String, Set<String>>{};
  String? module(String path) {
    final match = RegExp(r'^lib/modules/([^/]+)/').firstMatch(path);
    return match?.group(1);
  }

  for (final entry in sources.entries) {
    final source = entry.key;
    final unit = parseString(
      content: entry.value,
      throwIfDiagnostics: false,
    ).unit;
    final uris = <String>[];
    for (final directive in unit.directives) {
      if (directive is UriBasedDirective) {
        final value = directive.uri.stringValue;
        if (value != null) uris.add(value);
      }
      if (directive is NamespaceDirective) {
        for (final configuration in directive.configurations) {
          final value = configuration.uri.stringValue;
          if (value != null) uris.add(value);
        }
      }
      if (directive is PartOfDirective && directive.uri != null) {
        final value = directive.uri!.stringValue;
        if (value != null) uris.add(value);
      }
    }
    for (final uri in uris) {
      final target = uri.startsWith('package:vertree/')
          ? 'lib/${uri.substring('package:vertree/'.length)}'
          : uri.contains(':')
          ? uri
          : p.posix.normalize(p.posix.join(p.posix.dirname(source), uri));
      void reject(String rule) => result.add('$source -> $target [$rule]');
      final fromModule = module(source), toModule = module(target);
      if (source != 'lib/main.dart' &&
          (target == 'lib/main.dart' ||
              target == 'lib/app_runtime.dart' ||
              target == 'lib/app/desktop_app.dart')) {
        reject('entry-point-dependency');
      }
      if ((source.startsWith('lib/api/') ||
              source.startsWith('lib/service/')) &&
          (target.startsWith('lib/view/') ||
              target.startsWith('lib/adapters/ui/'))) {
        reject('backend-to-ui');
      }
      if (source.startsWith('lib/foundation/') &&
          target.startsWith('lib/') &&
          !target.startsWith('lib/foundation/')) {
        reject('foundation-outward-dependency');
      }
      if (fromModule != null) {
        if (target.startsWith('lib/core/') ||
            target.startsWith('lib/service/') ||
            target.startsWith('lib/component/') ||
            target.startsWith('lib/app/') ||
            target.startsWith('lib/api/') ||
            target.startsWith('lib/adapters/') ||
            target.startsWith('lib/view/')) {
          reject('module-to-legacy-or-adapter');
        }
        if (source.contains('/domain/') ||
            source.contains('/application/') ||
            source.contains('/ports/')) {
          if (target == 'dart:io' ||
              target == 'dart:ui' ||
              target.startsWith('package:flutter/') ||
              target.contains('/infrastructure/') ||
              target.startsWith('package:') &&
                  !target.startsWith('package:path/') &&
                  !target.startsWith('package:uuid/')) {
            reject('impure-inner-layer');
          }
        }
        if (source.contains('/domain/') &&
            (target.contains('/application/') || target.contains('/ports/'))) {
          reject('domain-outward-dependency');
        }
      }
      if (toModule != null &&
          fromModule != toModule &&
          target != 'lib/modules/$toModule/$toModule.dart' &&
          !source.startsWith('lib/app/')) {
        reject('module-internal-import');
      }
      if (fromModule != null && toModule != null && fromModule != toModule) {
        moduleEdges.putIfAbsent(fromModule, () => {}).add(toModule);
        const allowed = {
          'monitoring': {'snapshots', 'settings'},
          'versions': {'snapshots'},
          'automation': {
            'versions',
            'snapshots',
            'monitoring',
            'preview',
            'sharing',
            'settings',
          },
        };
        if (!(allowed[fromModule]?.contains(toModule) ?? false)) {
          reject('module-dependency-not-allowed');
        }
      }
      if (source == 'lib/file_access/file_access.dart' &&
          target.startsWith('lib/modules/')) {
        reject('file-access-business-dependency');
      }
    }
  }
  void visit(String node, List<String> path) {
    if (path.contains(node)) {
      result.add('module-cycle: ${[...path, node].join(' -> ')}');
      return;
    }
    for (final next in moduleEdges[node] ?? <String>{}) {
      visit(next, [...path, node]);
    }
  }

  for (final node in moduleEdges.keys) {
    visit(node, []);
  }
  return result;
}

void main(List<String> args) {
  final sources = <String, String>{};
  for (final file in Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>()) {
    if (file.path.endsWith('.dart')) {
      sources[file.path.replaceAll('\\', '/')] = file.readAsStringSync();
    }
  }
  final actual = violations(sources);
  for (final edge in actual.toList()..sort()) {
    stderr.writeln('ARCHITECTURE VIOLATION: $edge');
  }
  if (actual.isNotEmpty) {
    exitCode = 1;
    return;
  }
  stdout.writeln('Architecture passed (zero violations).');
}
