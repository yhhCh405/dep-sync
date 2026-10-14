import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../domain/workspace_manifest.dart';

class ManifestRepository {
  const ManifestRepository();

  WorkspaceManifest load({required Directory workspaceRoot}) => parse(
        File(p.join(workspaceRoot.path, '.dep-sync', 'manifest.yaml'))
            .readAsStringSync(),
      );

  WorkspaceManifest parse(String source) {
    final document = loadYaml(source);
    if (document is! YamlMap) {
      throw FormatException(
          'manifest.yaml must be a YAML map. Use workspace: {} for defaults.');
    }
    _keys(document, {'workspace', 'ignore_packages'}, 'manifest');
    final workspace = document['workspace'] ?? <String, Object>{};
    if (workspace is! Map) {
      throw FormatException('workspace must be a map.');
    }
    _keys(workspace, {'search_roots', 'default_clone_root'}, 'workspace');
    final searchRoots = workspace.containsKey('search_roots')
        ? _strings(workspace['search_roots'], 'workspace.search_roots')
        : ['apps', 'packages'];
    final cloneRoot = workspace['default_clone_root'] ?? 'packages';
    if (cloneRoot is! String || cloneRoot.trim().isEmpty) {
      throw FormatException(
          'workspace.default_clone_root must be a relative directory.');
    }
    for (final path in [...searchRoots, cloneRoot]) {
      validateRelativePath(path);
    }
    final ignored = document.containsKey('ignore_packages')
        ? _strings(document['ignore_packages'], 'ignore_packages')
        : <String>[];
    for (final name in ignored) {
      if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(name)) {
        throw FormatException(
            'ignore_packages uses exact dependency names, not paths or patterns: $name');
      }
    }
    return WorkspaceManifest(
      searchRoots: searchRoots,
      defaultCloneRoot: cloneRoot,
      ignorePackages: ignored.toSet(),
    );
  }

  void _keys(Map map, Set<String> allowed, String location) {
    for (final key in map.keys) {
      if (!allowed.contains(key)) {
        throw FormatException(
            'Unknown $location key "$key". Repository lists (projects) are no longer supported; declare dependencies in the consumer pubspec.yaml.');
      }
    }
  }

  List<String> _strings(Object? value, String field) {
    if (value is! List ||
        value.any((item) => item is! String || item.trim().isEmpty)) {
      throw FormatException('$field must be a list of nonempty strings.');
    }
    return value.cast<String>();
  }
}

void validateRelativePath(String path) {
  if (path.trim().isEmpty ||
      p.posix.isAbsolute(path) ||
      p.windows.isAbsolute(path) ||
      path.contains('\\') ||
      path.split('/').contains('..') ||
      path.split('/').contains('.git') ||
      path.contains(':') ||
      RegExp(r'[\x00-\x1f]').hasMatch(path)) {
    throw FormatException(
        'Paths must stay inside the workspace and use relative forward-slash paths: $path');
  }
}
