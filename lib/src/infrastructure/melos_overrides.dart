import 'package:yaml/yaml.dart';

/// Recognizes Melos-generated overrides and returns their path entries.
///
/// The marker must name every override, with no extra fields, comments, or
/// non-path structures. Scalar version pins are allowed and must be preserved
/// by callers. Verify targets against workspace members and check that the file
/// is untracked before migrating any path entries.
Map<String, String>? melosManagedPathOverrides(String source) {
  final lines = source.split('\n');
  final comments =
      lines.where((line) => line.trimLeft().startsWith('#')).toList();
  if (comments.length != 1 ||
      lines.where((line) => line.contains('#')).length != 1) {
    return null;
  }
  final marker = RegExp(r'^# melos_managed_dependency_overrides: (.+)$')
      .firstMatch(comments.single.trim());
  if (marker == null) return null;
  final names = marker[1]!.split(',').map((name) => name.trim()).toList();
  if (names
          .any((name) => !RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(name)) ||
      names.toSet().length != names.length) {
    return null;
  }
  final yaml = loadYaml(source);
  if (yaml is! Map ||
      yaml.keys
          .any((key) => key != 'dependency_overrides' && key != 'resolution') ||
      (yaml.containsKey('resolution') && yaml['resolution'] != 'workspace')) {
    return null;
  }
  final values = yaml['dependency_overrides'];
  if (values is! Map ||
      values.length != names.length ||
      values.keys.any((key) => !names.contains(key))) {
    return null;
  }
  final paths = <String, String>{};
  for (final entry in values.entries) {
    final value = entry.value;
    if (value is String) continue;
    if (value is! Map ||
        value.length != 1 ||
        value['path'] is! String ||
        (value['path'] as String).trim().isEmpty) {
      return null;
    }
    paths[entry.key as String] = value['path'] as String;
  }
  return paths;
}
