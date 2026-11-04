import 'dart:io';

import 'package:dep_sync/src/domain/dep_pull_use_case.dart';
import 'package:dep_sync/src/domain/logger.dart';
import 'package:dep_sync/src/domain/options.dart';
import 'package:dep_sync/src/infrastructure/process_runner.dart';
import 'package:dep_sync/src/infrastructure/workspace_pub_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture.dart';

class RecordingRunner implements ProcessExecutor {
  final calls = <List<Object?>>[];
  int exitCode = 0;
  bool missing = false;
  @override
  Future<CommandResult> run(String executable, List<String> arguments,
      {String? workingDirectory, Map<String, String>? environment}) async {
    calls.add([executable, arguments, workingDirectory]);
    if (missing) throw ProcessException(executable, arguments, 'missing');
    return CommandResult(exitCode: exitCode, stdout: 'resolved\n', stderr: '');
  }
}

void main() {
  late Fixture f;
  late RecordingRunner runner;
  setUp(() {
    f = Fixture();
    runner = RecordingRunner();
    f.manifest('workspace: {use_resolution_workspace: true}\n');
    f.pubspecFile.writeAsStringSync(
        'name: app\nenvironment: {sdk: ^3.6.0}\nresolution: workspace\n');
  });
  tearDown(() => f.dispose());
  Future<void> pull({bool skip = false}) =>
      DepPullUseCase(resolver: WorkspacePubResolver(runner: runner)).run(
          PullOptions(
              cwd: f.consumer.resolveSymbolicLinksSync(), skipPubGet: skip));
  void pin(Directory directory, String version, {bool legacy = false}) {
    final file = File(
        p.join(directory.path, legacy ? '.fvm/fvm_config.json' : '.fvmrc'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
        legacy ? '{"flutterSdkVersion":"$version"}' : '{"flutter":"$version"}');
  }

  test(
      'native Dart resolution runs after workspace generation without Git dependencies',
      () async {
    await pull();
    expect(runner.calls.single, [
      Platform.resolvedExecutable,
      ['pub', 'get'],
      f.workspace.resolveSymbolicLinksSync()
    ]);
    expect(
        File(p.join(f.workspace.resolveSymbolicLinksSync(),
                '.dep-sync/pub-get.log'))
            .readAsStringSync(),
        contains('resolved'));
  });
  test('consumer pin takes precedence over workspace pin', () async {
    pin(f.consumer, '3.41.9');
    pin(f.workspace, '3.27.1');
    await pull();
    expect(runner.calls, [
      [
        'fvm',
        ['install', '3.41.9'],
        f.consumer.resolveSymbolicLinksSync()
      ],
      [
        'fvm',
        ['flutter', 'pub', 'get', '--no-example'],
        f.consumer.resolveSymbolicLinksSync()
      ],
    ]);
  });
  test('workspace legacy pin is used when consumer has no pin', () async {
    pin(f.workspace, '3.27.1', legacy: true);
    await pull();
    expect(runner.calls.first, [
      'fvm',
      ['install', '3.27.1'],
      f.workspace.resolveSymbolicLinksSync()
    ]);
  });
  test('Flutter is detected in nested workspace members without a pin',
      () async {
    f.pubspecFile.writeAsStringSync(
        '${f.pubspecFile.readAsStringSync()}dependencies:\n  flutter: {sdk: flutter}\n');
    await pull();
    expect(
        runner.calls.single[0], Platform.isWindows ? 'flutter.bat' : 'flutter');
    expect(runner.calls.single[1], ['pub', 'get', '--no-example']);
  });
  for (final nested in [false, true]) {
    test(
        'detects Flutter membership supplied by ${nested ? 'nested' : 'root'} overrides',
        () async {
      void write(String path, String source) {
        final file = File(p.join(f.workspace.path, path));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(source);
      }

      write('pubspec.yaml',
          'name: root\nworkspace: ${nested ? '[apps/app]' : '[missing_package]'}\n');
      if (nested) {
        write(
            'apps/app/pubspec.yaml', 'name: app\nworkspace: [missing_child]\n');
        write(
            'apps/app/pubspec_overrides.yaml', 'workspace: [features/child]\n');
        write('apps/app/features/child/pubspec.yaml',
            'name: child\ndependencies:\n  flutter: {sdk: flutter}\n');
      } else {
        write('pubspec_overrides.yaml', 'workspace: [apps/app]\n');
        write('apps/app/pubspec.yaml',
            'name: app\ndependencies:\n  flutter: {sdk: flutter}\n');
      }
      await WorkspacePubResolver(runner: runner)
          .resolve(f.workspace, f.consumer, const Logger(verbose: false));
      expect(runner.calls.single[0],
          Platform.isWindows ? 'flutter.bat' : 'flutter');
      expect(runner.calls.single[1], ['pub', 'get', '--no-example']);
    });
  }
  test('uses effective dependency sections when selecting the SDK', () async {
    File(p.join(f.workspace.path, 'pubspec.yaml'))
        .writeAsStringSync('name: root\nworkspace: [apps/app]\n');
    f.pubspecFile.writeAsStringSync(
        'name: app\ndependencies: {flutter: {sdk: flutter}}\n');
    File(p.join(f.consumer.path, 'pubspec_overrides.yaml'))
        .writeAsStringSync('dependencies: {}\n');
    await WorkspacePubResolver(runner: runner)
        .resolve(f.workspace, f.consumer, const Logger(verbose: false));
    expect(runner.calls.single[0], Platform.resolvedExecutable);
  });
  test('skip flag and non-workspace mode do not invoke SDK commands', () async {
    await pull(skip: true);
    expect(runner.calls, isEmpty);
    f.manifest('workspace: {}\n');
    await pull();
    expect(runner.calls, isEmpty);
  });
  test('SDK installation failure stops before pub and reports log', () async {
    pin(f.consumer, '3.41.9');
    runner.exitCode = 7;
    await expectLater(
        pull(),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'failure', contains('exit 7'))));
    expect(runner.calls, hasLength(1));
    expect(
        File(p.join(f.workspace.resolveSymbolicLinksSync(), 'pubspec.yaml'))
            .existsSync(),
        true);
  });
  test('missing FVM never silently falls back to a different SDK', () async {
    pin(f.consumer, '3.41.9');
    runner.missing = true;
    await expectLater(
        pull(),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'FVM guidance', contains('Install FVM'))));
    expect(runner.calls, hasLength(1));
  });
  test('invalid consumer pin does not fall back to workspace pin', () async {
    pin(f.consumer, '-bad');
    pin(f.workspace, '3.27.1');
    await expectLater(pull(), throwsFormatException);
    expect(runner.calls, isEmpty);
  });
  test('direct resolver reports SDK output failures', () async {
    await pull(skip: true);
    runner.exitCode = 1;
    await expectLater(
        WorkspacePubResolver(runner: runner)
            .resolve(f.workspace, f.consumer, const Logger(verbose: false)),
        throwsStateError);
  });
}
