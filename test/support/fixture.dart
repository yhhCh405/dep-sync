import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Creates disposable workspaces and real local Git repositories for tests.
///
/// Create one in setUp and register [dispose] with tearDown. Use [remote] to make
/// a dependency source, [pubspec] to declare it, and [clone] for existing-checkout
/// scenarios. All files live under [root]; no external Git hosting is required.
class Fixture {
  /// Creates a temporary workspace, an app directory, and default manifest/pubspec files.
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

  /// The current consumer pubspec; follows [consumer] when a test relocates it.
  File get pubspecFile => File(p.join(consumer.path, 'pubspec.yaml'));

  /// Removes all fixture repositories and files; call after the test completes.
  void dispose() => root.deleteSync(recursive: true);

  /// Writes YAML to the workspace manifest, creating its parent directory.
  void manifest(String text) {
    final file = File(p.join(workspace.path, '.dep-sync', 'manifest.yaml'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  /// Writes a consumer with an older SDK constraint to detect accidental SDK rewrites.
  void pubspec(String dependencies) =>
      pubspecFile.writeAsStringSync('''name: app
# Consumer requirements are never rewritten.
environment:
  sdk: '>=2.18.0 <3.0.0'
$dependencies
''');

  /// Creates a local Git source on `main` with one committed package pubspec.
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

  /// Builds an indented Git dependency declaration for insertion under a pubspec section.
  String dependency(String name, Directory remote,
          {String ref = 'main', String path = ''}) =>
      '''  $name:
    git:
      url: '${remote.path.replaceAll('\\', '/')}'
      ref: $ref
      ${path.isEmpty ? '' : 'path: $path'}
''';

  /// Returns the expected destination beneath the fixture workspace package directory.
  Directory clonePath(String name) =>
      Directory(p.join(workspace.path, 'packages', name));

  /// Creates an existing dependency checkout, optionally using a custom folder name.
  Future<Directory> clone(Directory remote, {String? name}) async {
    final target = clonePath(name ?? p.basenameWithoutExtension(remote.path));
    target.parent.createSync(recursive: true);
    await git(target.parent, ['clone', remote.path, target.path]);
    return target;
  }

  /// Stages fixture files and commits with a test-local identity and disabled hooks.
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

  /// Returns the fixture repository HEAD hash for assertions.
  Future<String> head(Directory directory) =>
      git(directory, ['rev-parse', 'HEAD']);

  /// Parses the current consumer pubspec for assertions.
  dynamic get yaml => loadYaml(pubspecFile.readAsStringSync());
}

/// Runs real Git with hooks disabled and fails the test on a nonzero command exit.
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
