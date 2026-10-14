import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../domain/git_dependency.dart';
import 'manifest_repository.dart';

class PubspecRepository {
  const PubspecRepository();

  List<GitDependency> readGitDependencies(File file,
      {Set<String> ignored = const {}}) {
    final document = loadYaml(file.readAsStringSync());
    if (document is! YamlMap) {
      throw FormatException('pubspec.yaml must be a YAML map.');
    }
    final result = <GitDependency>[];
    for (final section in const [
      'dependencies',
      'dev_dependencies',
      'dependency_overrides'
    ]) {
      final values = document[section];
      if (values == null) continue;
      if (values is! YamlMap) {
        throw FormatException('$section must be a YAML map.');
      }
      for (final entry in values.entries) {
        final name = entry.key.toString();
        final value = entry.value;
        if (value is! YamlMap || !value.containsKey('git')) continue;
        final git = value['git'];
        if (git is! String && git is! YamlMap) {
          throw FormatException('$section.$name.git must be a URL or a map.');
        }
        final url = git is String ? git : (git as YamlMap)['url'];
        final ref = git is YamlMap ? git['ref'] ?? '' : '';
        final path = git is YamlMap ? git['path'] ?? '' : '';
        if (url is! String ||
            url.trim().isEmpty ||
            url.startsWith('-') ||
            RegExp(r'[\x00-\x1f]').hasMatch(url)) {
          throw FormatException(
              '$section.$name.git.url must be a nonempty Git URL.');
        }
        if (url.contains('://') &&
            !{'https', 'http', 'ssh', 'git', 'file'}
                .contains(Uri.parse(url).scheme)) {
          throw FormatException('Unsupported Git URL scheme for $name.');
        }
        if (ref is! String ||
            ref.startsWith('-') ||
            RegExp(r'[\x00-\x1f]').hasMatch(ref)) {
          throw FormatException(
              '$section.$name.git.ref must be a branch, tag, or commit string.');
        }
        if (path is! String) {
          throw FormatException('$section.$name.git.path must be a string.');
        }
        if (path.isNotEmpty) validateRelativePath(path);
        if (git is YamlMap &&
            git.containsKey('tag_pattern') &&
            !ignored.contains(name)) {
          throw FormatException(
              '$name uses git.tag_pattern, which dep-sync cannot pin. Add it to ignore_packages or use an explicit ref.');
        }
        result.add(GitDependency(
            section: section, name: name, url: url, ref: ref, path: path));
      }
    }
    return result;
  }

  /// Builds the whole edit before atomically replacing the original file.
  void updateGitRefs(File file, Map<GitDependency, String> refs,
      {required String original}) {
    final editor = YamlEditor(original);
    for (final entry in refs.entries) {
      final dep = entry.key;
      final path = [dep.section, dep.name, 'git'];
      final value = editor.parseAt(path).value;
      if (value is String) {
        editor.update(path, {'url': value, 'ref': entry.value});
      } else {
        editor.update([...path, 'ref'], entry.value);
      }
    }
    if (file.readAsStringSync() != original) {
      throw StateError(
          'pubspec.yaml changed during synchronization. No refs were written; retry.');
    }
    final updated = editor.toString();
    if (updated == original) return;
    final temporaryDirectory = file.parent.createTempSync('.dep-sync-write-');
    try {
      final temporary = File('${temporaryDirectory.path}/pubspec.yaml');
      // Copy first to retain the permissions of the original file.
      file.copySync(temporary.path);
      temporary.writeAsStringSync(updated, flush: true);
      temporary.renameSync(file.path);
    } finally {
      temporaryDirectory.deleteSync(recursive: true);
    }
  }
}
