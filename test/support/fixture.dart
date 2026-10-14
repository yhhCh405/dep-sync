import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

class Fixture {
  Fixture() : root = Directory.systemTemp.createTempSync('dep_sync_test_') {
    workspace = Directory(p.join(root.path, 'workspace'))..createSync();
    consumer = Directory(p.join(workspace.path, 'apps', 'app'))
      ..createSync(recursive: true);
    manifest('workspace: {}\n');
    pubspec('');
  }
  final Directory root;
  late final Directory workspace;
  late Directory consumer;
  File get pubspecFile => File(p.join(consumer.path, 'pubspec.yaml'));
  void dispose() => root.deleteSync(recursive: true);
  void manifest(String text) {
    final file = File(p.join(workspace.path, '.dep-sync', 'manifest.yaml'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  void pubspec(String dependencies) =>
      pubspecFile.writeAsStringSync('''name: app
# Consumer requirements are never rewritten.
environment:
  sdk: '>=2.18.0 <3.0.0'
$dependencies
''');

  Future<Directory> remote(String name,
      {String? packageName, String packagePath = ''}) async {
    final directory = Directory(p.join(root.path, 'remotes', '$name.git'))
      ..createSync(recursive: true);
    await git(directory, ['init', '-b', 'main']);
    await git(directory, ['config', 'user.name', 'Test']);
    await git(directory, ['config', 'user.email', 'test@example.com']);
    final file = File(p.join(directory.path, packagePath, 'pubspec.yaml'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
        "name: ${packageName ?? name}\nenvironment:\n  sdk: '>=2.18.0 <3.0.0'\n");
    await commit(directory, 'initial');
    return directory;
  }

  String dependency(String name, Directory remote,
          {String ref = 'main', String path = ''}) =>
      '''  $name:
    git:
      url: '${remote.path.replaceAll('\\', '/')}'
      ref: $ref
      ${path.isEmpty ? '' : 'path: $path'}
''';
  Directory clonePath(String name) =>
      Directory(p.join(workspace.path, 'packages', name));
  Future<Directory> clone(Directory remote, {String? name}) async {
    final target = clonePath(name ?? p.basenameWithoutExtension(remote.path));
    target.parent.createSync(recursive: true);
    await git(target.parent, ['clone', remote.path, target.path]);
    return target;
  }

  Future<void> commit(Directory directory, String message) async {
    await git(directory, ['add', '.']);
    await git(directory, [
      '-c',
      'user.name=Test',
      '-c',
      'user.email=test@example.com',
      'commit',
      '-m',
      message
    ]);
  }

  Future<String> head(Directory directory) =>
      git(directory, ['rev-parse', 'HEAD']);
  dynamic get yaml => loadYaml(pubspecFile.readAsStringSync());
}

Future<String> git(Directory directory, List<String> arguments) async {
  final result = await Process.run(
      'git',
      [
        '-c',
        'core.hooksPath=${Platform.isWindows ? 'NUL' : '/dev/null'}',
        ...arguments
      ],
      workingDirectory: directory.path);
  if (result.exitCode != 0) {
    throw StateError('git $arguments: ${result.stderr}');
  }
  return result.stdout.toString().trim();
}
