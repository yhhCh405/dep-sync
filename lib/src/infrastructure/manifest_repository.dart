import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../domain/workspace_manifest.dart';

/// Parses `.dep-sync/manifest.yaml` into validated [WorkspaceManifest] settings.
///
/// Use [load] for a known workspace root or [parse] for YAML already in memory.
/// Only workspace locations and package exclusions are accepted. Legacy project
/// lists, invalid field types, and escaping paths fail with [FormatException].
class ManifestRepository {
  /// Creates a stateless manifest reader.
  const ManifestRepository();

  /// Reads and validates the manifest beneath [workspaceRoot]; file errors propagate.
  WorkspaceManifest load({required Directory workspaceRoot}) => parse(
        File(p.join(workspaceRoot.path, '.dep-sync', 'manifest.yaml'))
            .readAsStringSync(),
      );

  /// Validates YAML [source] and applies defaults for omitted settings.
  ///
  /// This performs lexical path checks only; repository discovery separately
  /// checks existing filesystem paths for symlinks.
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

  /// Rejects unsupported keys so configuration mistakes cannot silently take effect.
  void _keys(Map map, Set<String> allowed, String location) {
    for (final key in map.keys) {
      if (!allowed.contains(key)) {
        throw FormatException(
            'Unknown $location key "$key". Repository lists (projects) are no longer supported; declare dependencies in the consumer pubspec.yaml.');
      }
    }
  }

  /// Checks that a YAML field is a list of nonempty strings, or throws.
  List<String> _strings(Object? value, String field) {
    if (value is! List ||
        value.any((item) => item is! String || item.trim().isEmpty)) {
      throw FormatException('$field must be a list of nonempty strings.');
    }
    return value.cast<String>();
  }
}

/// Rejects absolute, traversing, Git-metadata, or unsupported path spellings.
///
/// Use for manifest directories and repository-relative package paths before
/// joining them to a trusted root. This lexical check does not inspect symlinks.
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
