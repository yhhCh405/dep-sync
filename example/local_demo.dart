import 'dart:io';
import 'package:dep_sync/src/domain/dep_pull_use_case.dart';
import 'package:dep_sync/src/domain/dep_push_use_case.dart';
import 'package:dep_sync/src/domain/options.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

Future<void> main() async {
  final temporary = Directory.systemTemp.createTempSync('dep_sync_demo_');
  try {
    final remote = Directory(p.join(temporary.path, 'shared_widgets.git'))
      ..createSync();
    await git(remote, ['init', '-b', 'main']);
    File(p.join(remote.path, 'pubspec.yaml'))
        .writeAsStringSync('name: shared_widgets\n');
    await git(remote, ['add', '.']);
    await git(remote, [
      '-c',
      'user.name=Demo',
      '-c',
      'user.email=demo@example.com',
      'commit',
      '-m',
      'Initial package'
    ]);
    final workspace = Directory(p.join(temporary.path, 'workspace'))
      ..createSync();
    final manifest = File(p.join(workspace.path, '.dep-sync', 'manifest.yaml'));
    manifest.parent.createSync();
    manifest.writeAsStringSync('workspace: {}\nignore_packages: []\n');
    final consumer = Directory(p.join(workspace.path, 'apps', 'app'))
      ..createSync(recursive: true);
    final pubspec = File(p.join(consumer.path, 'pubspec.yaml'));
    pubspec.writeAsStringSync('''name: demo_app
environment:
  sdk: '>=2.18.0 <3.0.0'
dependencies:
  shared_widgets:
    git:
      url: '${remote.path.replaceAll('\\', '/')}'
      ref: main
''');
    await DepPullUseCase().run(PullOptions(cwd: consumer.path));
    await DepPushUseCase().run(PushOptions(cwd: consumer.path));
    final result = loadYaml(pubspec.readAsStringSync());
    final hash = await git(remote, ['rev-parse', 'HEAD']);
    if (result['environment']['sdk'] != '>=2.18.0 <3.0.0' ||
        result['dependencies']['shared_widgets']['git']['ref'] != hash) {
      throw StateError('Demo verification failed.');
    }
    stdout.writeln(
        'Demo passed: dependency cloned and pinned, consumer SDK unchanged.');
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

Future<String> git(Directory directory, List<String> args) async {
  final result = await Process.run(
      'git',
      [
        '-c',
        'core.hooksPath=${Platform.isWindows ? 'NUL' : '/dev/null'}',
        ...args
      ],
      workingDirectory: directory.path);
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
  return result.stdout.toString().trim();
}
