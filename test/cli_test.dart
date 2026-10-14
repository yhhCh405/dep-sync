import 'dart:io';
import 'package:dep_sync/src/cli/dep_sync_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'support/fixture.dart';

void main() {
  final packageRoot = Directory.current.path;
  Future<ProcessResult> cli(String bin, List<String> args) => Process.run(
        Platform.resolvedExecutable,
        ['run', p.join(packageRoot, 'bin', '$bin.dart'), ...args],
        workingDirectory: packageRoot,
      );
  test('version agrees with package metadata', () async {
    expect(packageVersion,
        loadYaml(File('pubspec.yaml').readAsStringSync())['version']);
    for (final name in ['dep_sync', 'dep_pull', 'dep_push']) {
      final result = await cli(name, ['--version']);
      expect(result.exitCode, 0);
      expect(result.stdout.toString(), contains(packageVersion));
    }
  });
  test('all executable entrypoints provide help', () async {
    for (final name in ['dep_sync', 'dep_pull', 'dep_push']) {
      final result = await cli(name, ['--help']);
      expect(result.exitCode, 0);
      expect(result.stdout.toString(), contains('Usage:'));
    }
  });
  test('invalid arguments fail without a stack trace', () async {
    final result = await cli('dep_sync', ['pull', '--melos-only']);
    expect(result.exitCode, 64);
    expect(result.stderr.toString(), contains('melos-only'));
    expect(result.stderr.toString(), isNot(contains('Unhandled exception')));
  });
  test('missing configuration is an actionable nonzero failure', () async {
    final fixture = Fixture();
    addTearDown(fixture.dispose);
    File(p.join(fixture.workspace.path, '.dep-sync', 'manifest.yaml'))
        .deleteSync();
    final result =
        await cli('dep_sync', ['pull', '--cwd', fixture.consumer.path]);
    expect(result.exitCode, 1);
    expect(result.stderr.toString(), contains('.dep-sync/manifest.yaml'));
    expect(result.stderr.toString(), isNot(contains('Unhandled exception')));
  });
  test('aliases can run a no-op consumer without invoking SDK tooling',
      () async {
    final fixture = Fixture();
    addTearDown(fixture.dispose);
    for (final name in ['dep_pull', 'dep_push']) {
      final result = await cli(name, ['--cwd', fixture.consumer.path]);
      expect(result.exitCode, 0);
      expect(result.stdout.toString(), contains('No managed Git dependencies'));
    }
  });
}
