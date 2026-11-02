import 'dart:io';
import 'dart:convert';
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
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
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
  test('aliases print the product notice once before output', () async {
    for (final name in ['dep_pull', 'dep_push']) {
      final result = await cli(name, ['--version']);
      expect(result.exitCode, 0);
      final output = result.stdout.toString();
      expect(output, startsWith(formatDepSyncNotice()));
      expect(output,
          contains('Git Multi-Repos Workspace Dependencies Synchronization'));
      expect(output, isNot(contains('\x1b[')));
      expect('DEP-SYNC'.allMatches(output).length, 1);
      expect(output.indexOf('version'),
          greaterThan(output.indexOf('Synchronization')));
    }
  });
  test('notice has aligned borders and optional color without changing layout',
      () {
    final plain = formatDepSyncNotice();
    final lines = plain.trim().split('\n');
    expect(lines, hasLength(4));
    expect(lines.map((line) => line.length).toSet(), hasLength(1));
    final colored = formatDepSyncNotice(ansi: true);
    expect(colored, contains('\x1b[1;36m'));
    expect(colored.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), ''), plain);
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
