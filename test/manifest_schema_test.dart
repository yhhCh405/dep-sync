import 'dart:convert';
import 'dart:io';

import 'package:dep_sync/src/infrastructure/manifest_repository.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final schema =
      jsonDecode(File('schema/manifest.schema.json').readAsStringSync()) as Map;
  final properties = schema['properties'] as Map;
  final workspace = properties['workspace'] as Map;
  final fields = workspace['properties'] as Map;

  test('schema documents all supported fields for YAML hover and completion',
      () {
    expect(properties.keys, unorderedEquals(['workspace', 'ignore_packages']));
    expect(
        fields.keys,
        unorderedEquals([
          'search_roots',
          'default_clone_root',
          'use_resolution_workspace',
        ]));
    expect(schema['additionalProperties'], false);
    expect(workspace['additionalProperties'], false);
    for (final value in [...properties.values, ...fields.values]) {
      expect(
          (value as Map)['description'],
          isA<String>().having((s) => s.length,
              'useful hover description length', greaterThan(30)));
    }
    expect(fields['use_resolution_workspace']['type'], 'boolean');
    expect(fields['use_resolution_workspace']['default'], false);
  });

  test('schema modelines resolve and all example manifests parse', () {
    for (final file
        in Directory('example').listSync(recursive: true).whereType<File>()) {
      if (!file.path
          .endsWith('${p.separator}.dep-sync${p.separator}manifest.yaml')) {
        continue;
      }
      final source = file.readAsStringSync();
      final modeline =
          RegExp(r'^# yaml-language-server: \$schema=(.+)$', multiLine: true)
              .firstMatch(source);
      expect(modeline, isNotNull, reason: file.path);
      expect(
          File(p.normalize(p.join(file.parent.path, modeline![1])))
              .existsSync(),
          true,
          reason: file.path);
      const ManifestRepository().parse(source);
    }
  });

  test('schema path rules agree with parser examples', () {
    final pattern =
        RegExp(schema['definitions']['relativePath']['pattern'] as String);
    for (final path in [
      'packages',
      '.',
      'libraries/shared',
      'products/mobile',
      'libs/vendor'
    ]) {
      expect(pattern.hasMatch(path), true, reason: path);
    }
    for (final path in [
      '',
      ' ',
      '../outside',
      '/tmp',
      'C:/outside',
      'a/../b',
      'a/.git/b',
      r'a\b'
    ]) {
      expect(pattern.hasMatch(path), false, reason: path);
    }
  });

  test('workspace example 2 declares compatible Pub resolution and SDKs', () {
    final manifest = const ManifestRepository()
        .load(workspaceRoot: Directory('example/example-workspace-2'));
    expect(manifest.useResolutionWorkspace, true);
    for (final file in Directory('example/example-workspace-2')
        .listSync(recursive: true)
        .whereType<File>()) {
      if (!file.path.endsWith('pubspec.yaml')) continue;
      final yaml = loadYaml(file.readAsStringSync());
      expect(yaml['resolution'], 'workspace');
      expect(yaml['environment']['sdk'], '^3.6.0');
    }
  });
}
