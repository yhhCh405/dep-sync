import 'dart:convert';
import 'dart:io';

import 'package:dep_sync/src/domain/dep_pull_use_case.dart';
import 'package:dep_sync/src/domain/dep_push_use_case.dart';
import 'package:dep_sync/src/domain/options.dart';
import 'package:dep_sync/src/infrastructure/git_client.dart';
import 'package:dep_sync/src/infrastructure/pub_workspace_repository.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/fixture.dart';

void main() {
  late Fixture f;
  setUp(() {
    f = Fixture();
    f.manifest('workspace: {use_resolution_workspace: true}\n');
  });
  tearDown(() => f.dispose());
  File file(String path) => File(p.join(f.workspace.path, path));
  Future<void> pull({bool fresh = false, bool force = false}) =>
      DepPullUseCase()
          .run(PullOptions(cwd: f.consumer.path, fresh: fresh, force: force));
  void app(String dependencies, {bool resolution = false}) {
    f.pubspecFile.writeAsStringSync('''name: app
environment:
  sdk: ^3.6.0
${resolution ? 'resolution: workspace' : ''}
$dependencies
''');
  }

  Future<Directory> remote(String name, {String packagePath = ''}) async {
    final repo = await f.remote(name, packagePath: packagePath);
    File(p.join(repo.path, packagePath, 'pubspec.yaml'))
        .writeAsStringSync('name: $name\nenvironment:\n  sdk: ^3.6.0\n');
    File(p.join(repo.path, '.gitignore'))
        .writeAsStringSync('.dart_tool/\npubspec.lock\n');
    await f.commit(repo, 'Support Pub workspaces');
    return repo;
  }

  test(
      'generates usable workspace, preserves pubspecs, and supports repeat pull/push',
      () async {
    final repo = await remote('shared');
    app('dependencies:\n${f.dependency('shared', repo)}', resolution: true);
    final before = f.pubspecFile.readAsStringSync();
    await pull();
    expect(loadYaml(file('pubspec.yaml').readAsStringSync())['workspace'],
        ['apps/app', 'packages/shared']);
    expect(file('packages/shared/pubspec_overrides.yaml').readAsStringSync(),
        generatedResolutionOverride);
    expect(file('apps/app/pubspec_overrides.yaml').existsSync(), false);
    expect(f.pubspecFile.readAsStringSync(), before);
    final result = await Process.run(
        Platform.resolvedExecutable, ['pub', 'get'],
        workingDirectory: f.workspace.path);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    await pull();
    await DepPushUseCase().run(PushOptions(cwd: f.consumer.path));
    expect(f.pubspecFile.readAsStringSync(), contains(await f.head(repo)));
    // The generated override is not a user change; edited overrides still are.
    expect(await GitClient().hasLocalChanges(f.clonePath('shared')), false);
    file('packages/shared/pubspec_overrides.yaml')
        .writeAsStringSync('$generatedResolutionOverride# user edit\n');
    expect(await GitClient().hasLocalChanges(f.clonePath('shared')), true);
    await expectLater(pull(), throwsStateError);
  });

  test('existing user root and overrides are reused without edits', () async {
    final repo = await remote('shared');
    app('dependencies:\n${f.dependency('shared', repo)}', resolution: true);
    final source = 'name: team_workspace\nenvironment: {sdk: ^3.6.0}\n'
        'workspace: [apps/app, packages/shared]\n# keep this\n';
    file('pubspec.yaml').writeAsStringSync(source);
    final overrides = file('apps/app/pubspec_overrides.yaml')
      ..writeAsStringSync('dependency_overrides: {collection: ^1.19.0}\n');
    await pull();
    expect(file('pubspec.yaml').readAsStringSync(), source);
    expect(overrides.readAsStringSync(),
        'dependency_overrides: {collection: ^1.19.0}\n');
  });

  test('rejects incompatible SDK before applying clones or workspace files',
      () async {
    final repo = await remote('shared');
    f.pubspec('dependencies:\n${f.dependency('shared', repo)}');
    final before = f.pubspecFile.readAsStringSync();
    await expectLater(
        pull(),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('3.6.0'))));
    expect(f.clonePath('shared').existsSync(), false);
    expect(file('pubspec.yaml').existsSync(), false);
    expect(f.pubspecFile.readAsStringSync(), before);
  });

  test('preserves conflicting user overrides and existing checkout HEAD',
      () async {
    final repo = await remote('shared');
    final clone = await f.clone(repo);
    final hash = await f.head(clone);
    app('dependencies:\n${f.dependency('shared', repo)}');
    file('apps/app/pubspec_overrides.yaml')
        .writeAsStringSync('dependency_overrides: {custom: any}\n');
    await expectLater(pull(), throwsStateError);
    expect(await f.head(clone), hash);
    expect(file('pubspec.yaml').existsSync(), false);
    expect(file('apps/app/pubspec_overrides.yaml').readAsStringSync(),
        'dependency_overrides: {custom: any}\n');
  });

  test('refuses to overwrite existing root missing members', () async {
    app('');
    const source =
        'name: user_root\nenvironment: {sdk: ^3.6.0}\nworkspace: []\n';
    file('pubspec.yaml').writeAsStringSync(source);
    await expectLater(pull(), throwsStateError);
    expect(file('pubspec.yaml').readAsStringSync(), source);
    expect(file('apps/app/pubspec_overrides.yaml').existsSync(), false);
  });

  test('includes embedded path dependencies and nested workspace members once',
      () async {
    app('dependencies:\n  feature:\n    path: features/feature\n');
    final feature = file('apps/app/features/feature/pubspec.yaml');
    feature.parent.createSync(recursive: true);
    feature.writeAsStringSync('name: feature\nenvironment: {sdk: ^3.6.0}\n'
        'workspace: [utils]\ndependencies:\n  app: {path: ../..}\n');
    final utils = file('apps/app/features/feature/utils/pubspec.yaml');
    utils.parent.createSync(recursive: true);
    utils
        .writeAsStringSync('name: feature_utils\nenvironment: {sdk: ^3.6.0}\n');
    await pull();
    expect(loadYaml(file('pubspec.yaml').readAsStringSync())['workspace'], [
      'apps/app',
      'apps/app/features/feature',
    ]);
    final result = await Process.run(
        Platform.resolvedExecutable, ['pub', 'get'],
        workingDirectory: f.workspace.path);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('uses new commit pubspec rather than existing working tree', () async {
    final repo = await remote('shared');
    final clone = await f.clone(repo);
    File(p.join(repo.path, 'pubspec.yaml')).writeAsStringSync(
        'name: shared\nenvironment: {sdk: ^3.6.0}\nresolution: workspace\n');
    await f.commit(repo, 'Enable resolution');
    app('dependencies:\n${f.dependency('shared', repo, ref: await f.head(repo))}');
    await pull();
    expect(await f.head(clone), await f.head(repo));
    expect(file('packages/shared/pubspec_overrides.yaml').existsSync(), false);
  });

  test('cleans stale owned overrides when dependencies are removed', () async {
    final repo = await remote('shared');
    app('dependencies:\n${f.dependency('shared', repo)}');
    await pull();
    app('');
    await pull();
    expect(loadYaml(file('pubspec.yaml').readAsStringSync())['workspace'],
        ['apps/app']);
    expect(file('packages/shared/pubspec_overrides.yaml').existsSync(), false);
    expect(f.clonePath('shared').existsSync(), true);
  });

  test('false leaves generated configuration untouched', () async {
    app('');
    await pull();
    final before = file('pubspec.yaml').readAsStringSync();
    f.manifest('workspace: {use_resolution_workspace: false}\n');
    await pull();
    expect(file('pubspec.yaml').readAsStringSync(), before);
  });

  test('edited generated root is never overwritten', () async {
    app('');
    await pull();
    file('pubspec.yaml').writeAsStringSync(
        '${file('pubspec.yaml').readAsStringSync()}# mine\n');
    await expectLater(pull(), throwsStateError);
    expect(file('pubspec.yaml').readAsStringSync(), endsWith('# mine\n'));
  });

  test('custom clone root and multiple packages in one repo', () async {
    f.manifest('workspace: {search_roots: [libraries], '
        'default_clone_root: libraries/vendor, use_resolution_workspace: true}\n');
    final repo = await remote('shared', packagePath: 'core');
    File(p.join(repo.path, 'utils', 'pubspec.yaml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('name: utils\nenvironment: {sdk: ^3.6.0}\n');
    await f.commit(repo, 'Add utils');
    app('dependencies:\n${f.dependency('shared', repo, path: 'core')}'
        '${f.dependency('utils', repo, path: 'utils')}');
    await pull();
    expect(loadYaml(file('pubspec.yaml').readAsStringSync())['workspace'], [
      'apps/app',
      'libraries/vendor/shared/core',
      'libraries/vendor/shared/utils',
    ]);
  });

  test('rejects paths outside workspace before writing', () async {
    app('dependencies:\n  other: {path: ../../../other}\n');
    await expectLater(pull(), throwsFormatException);
    expect(file('pubspec.yaml').existsSync(), false);
  });

  test('ignored Git dependency is not made a workspace member', () async {
    final repo = await remote('shared');
    f.manifest(
        'workspace: {use_resolution_workspace: true}\nignore_packages: [shared]\n');
    app('dependencies:\n${f.dependency('shared', repo)}');
    await pull();
    expect(loadYaml(file('pubspec.yaml').readAsStringSync())['workspace'],
        ['apps/app']);
    expect(f.clonePath('shared').existsSync(), false);
  });

  test(
      'fresh requires force for generated local overrides and regenerates them',
      () async {
    final repo = await remote('shared');
    app('dependencies:\n${f.dependency('shared', repo)}');
    await pull();
    await expectLater(pull(fresh: true), throwsStateError);
    await pull(fresh: true, force: true);
    expect(file('packages/shared/pubspec_overrides.yaml').readAsStringSync(),
        generatedResolutionOverride);
  });

  test('tracked changes resembling generated files remain protected', () async {
    final repo = await remote('shared');
    File(p.join(repo.path, 'pubspec_overrides.yaml'))
        .writeAsStringSync('resolution: workspace\n');
    await f.commit(repo, 'Track override');
    final clone = await f.clone(repo);
    file('packages/shared/pubspec_overrides.yaml')
        .writeAsStringSync(generatedResolutionOverride);
    expect(await GitClient().hasLocalChanges(clone), true);
  });

  test('duplicate names fail without any config writes', () async {
    app('workspace: [features/duplicate]\n');
    final duplicate = file('apps/app/features/duplicate/pubspec.yaml');
    duplicate.parent.createSync(recursive: true);
    duplicate.writeAsStringSync('name: app\nenvironment: {sdk: ^3.6.0}\n');
    await expectLater(pull(), throwsStateError);
    expect(file('pubspec.yaml').existsSync(), false);
  });

  test('unsafe state paths cannot cause writes outside workspace', () async {
    app('');
    file('.dep-sync/pub-workspace-state.json').writeAsStringSync(jsonEncode({
      'version': 1,
      'files': {'../pubspec.yaml': 'mine'},
    }));
    await expectLater(pull(), throwsStateError);
    expect(file('pubspec.yaml').existsSync(), false);
  });
  test(
      'ancestor pubspecs are included so Pub has no stray intermediate package',
      () async {
    app('dependencies:\n  feature: {path: features/feature}\n');
    final parent = file('apps/app/features/pubspec.yaml');
    parent.parent.createSync(recursive: true);
    parent
        .writeAsStringSync('name: feature_group\nenvironment: {sdk: ^3.6.0}\n');
    final child = file('apps/app/features/feature/pubspec.yaml');
    child.parent.createSync(recursive: true);
    child.writeAsStringSync('name: feature\nenvironment: {sdk: ^3.6.0}\n');
    await pull();
    expect(loadYaml(file('pubspec.yaml').readAsStringSync())['workspace'], [
      'apps/app',
      'apps/app/features',
      'apps/app/features/feature',
    ]);
    final result = await Process.run(
        Platform.resolvedExecutable, ['pub', 'get'],
        workingDirectory: f.workspace.path);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('an ignored package keeps even an edited previously generated override',
      () async {
    final repo = await remote('shared');
    app('dependencies:\n${f.dependency('shared', repo)}');
    await pull();
    final override = file('packages/shared/pubspec_overrides.yaml');
    override.writeAsStringSync(
        '$generatedResolutionOverride# personal configuration\n');
    final before = override.readAsStringSync();
    f.manifest(
        'workspace: {use_resolution_workspace: true}\nignore_packages: [shared]\n');
    await pull();
    expect(override.readAsStringSync(), before);
    expect(loadYaml(file('pubspec.yaml').readAsStringSync())['workspace'],
        ['apps/app']);
  });

  test('a root override cannot silently replace generated membership',
      () async {
    app('');
    file('pubspec_overrides.yaml').writeAsStringSync('workspace: []\n');
    await expectLater(pull(), throwsStateError);
    expect(file('pubspec.yaml').existsSync(), false);
    expect(
        file('pubspec_overrides.yaml').readAsStringSync(), 'workspace: []\n');
  });

  test('conflicting SDK ranges are rejected without changing constraints',
      () async {
    final repo = await remote('shared');
    File(p.join(repo.path, 'pubspec.yaml')).writeAsStringSync(
        'name: shared\nenvironment: {sdk: ">=3.10.0 <4.0.0"}\n');
    await f.commit(repo, 'New SDK');
    app('dependencies:\n${f.dependency('shared', repo)}');
    f.pubspecFile.writeAsStringSync(f.pubspecFile
        .readAsStringSync()
        .replaceAll('^3.6.0', '">=3.6.0 <3.7.0"'));
    await expectLater(pull(), throwsStateError);
    expect(f.clonePath('shared').existsSync(), false);
  });

  test('consumer at the workspace root keeps its existing compatible pubspec',
      () async {
    final repo = await remote('shared');
    f.consumer = f.workspace;
    app('workspace: [packages/shared]\ndependencies:\n${f.dependency('shared', repo)}');
    final before = f.pubspecFile.readAsStringSync();
    await pull();
    expect(f.pubspecFile.readAsStringSync(), before);
    expect(file('pubspec_overrides.yaml').existsSync(), false);
    expect(file('packages/shared/pubspec_overrides.yaml').existsSync(), true);
  });

  test('symlink output files are rejected without writing through them',
      () async {
    if (!Platform.isWindows) {
      app('');
      final external = File(p.join(f.root.path, 'outside.yaml'))
        ..writeAsStringSync('name: outside\n');
      Link(file('pubspec.yaml').path).createSync(external.path);
      await expectLater(pull(), throwsStateError);
      expect(external.readAsStringSync(), 'name: outside\n');
    }
  });
  test(
      'migrates redundant Melos path overrides before Pub workspace resolution',
      () async {
    final bridgeRepo = await remote('bridge');
    final repo = await remote('shared');
    File(p.join(repo.path, 'pubspec.yaml')).writeAsStringSync(
        'name: shared\nenvironment: {sdk: ^3.6.0}\ndependencies:\n'
        '${f.dependency('bridge', bridgeRepo)}');
    await f.commit(repo, 'Depend on bridge');
    final clone = await f.clone(repo);
    final ignore = File(p.join(clone.path, '.git', 'info', 'exclude'));
    ignore.writeAsStringSync('pubspec_overrides.yaml\n', mode: FileMode.append);
    final override = file('packages/shared/pubspec_overrides.yaml');
    override.writeAsStringSync('# melos_managed_dependency_overrides: bridge\n'
        'dependency_overrides:\n  bridge:\n    path: ../bridge\n');
    app('dependencies:\n${f.dependency('shared', repo)}${f.dependency('bridge', bridgeRepo)}');
    final before = File(p.join(clone.path, 'pubspec.yaml')).readAsStringSync();
    await pull();
    expect(
        loadYaml(override.readAsStringSync())['dependency_overrides'], isNull);
    expect(File(p.join(clone.path, 'pubspec.yaml')).readAsStringSync(), before);
    final result = await Process.run(
        Platform.resolvedExecutable, ['pub', 'get'],
        workingDirectory: f.workspace.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    await pull();
    expect(loadYaml(file('pubspec.yaml').readAsStringSync())['workspace'],
        ['apps/app', 'packages/bridge', 'packages/shared']);
  });
  test(
      'removes stale Melos overrides when package already declares workspace resolution',
      () async {
    final bridgeRepo = await remote('bridge');
    final repo = await remote('shared');
    File(p.join(repo.path, 'pubspec.yaml')).writeAsStringSync(
        'name: shared\nenvironment: {sdk: ^3.6.0}\nresolution: workspace\n'
        'dependencies:\n${f.dependency('bridge', bridgeRepo)}');
    await f.commit(repo, 'Use workspace resolution');
    final clone = await f.clone(repo);
    File(p.join(clone.path, '.git', 'info', 'exclude'))
        .writeAsStringSync('pubspec_overrides.yaml\n', mode: FileMode.append);
    final override = file('packages/shared/pubspec_overrides.yaml')
      ..writeAsStringSync('# melos_managed_dependency_overrides: bridge\n'
          'dependency_overrides:\n  bridge: {path: ../bridge}\n');
    app('dependencies:\n${f.dependency('shared', repo)}${f.dependency('bridge', bridgeRepo)}');
    await pull();
    expect(override.existsSync(), false);
    final result = await Process.run(
        Platform.resolvedExecutable, ['pub', 'get'],
        workingDirectory: f.workspace.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    await pull();
  });

  test('user member overrides fail preflight without rewriting configuration',
      () async {
    final repo = await remote('shared');
    app(
        'dependencies:\n${f.dependency('shared', repo)}\n'
        'dependency_overrides:\n  shared: {path: ../../packages/shared}\n',
        resolution: true);
    final before = f.pubspecFile.readAsStringSync();
    await expectLater(
        pull(),
        throwsA(isA<StateError>().having(
            (error) => error.message,
            'actionable conflict',
            contains('Remove dependency_overrides.shared'))));
    expect(f.pubspecFile.readAsStringSync(), before);
    expect(f.clonePath('shared').existsSync(), false);
    expect(file('pubspec.yaml').existsSync(), false);
  });

  test('non-member path overrides stay outside generated workspace membership',
      () async {
    app(
        'dependencies:\n  external_sdk: any\ndependency_overrides:\n'
        '  external_sdk: {path: ../external}\n',
        resolution: true);
    final external = file('apps/external/pubspec.yaml');
    external.parent.createSync(recursive: true);
    external.writeAsStringSync(
        'name: external_sdk\nversion: 1.0.0\nenvironment: {sdk: ^3.6.0}\n');
    final before = f.pubspecFile.readAsStringSync();
    await pull();
    expect(loadYaml(file('pubspec.yaml').readAsStringSync())['workspace'],
        ['apps/app']);
    expect(f.pubspecFile.readAsStringSync(), before);
    final result = await Process.run(
        Platform.resolvedExecutable, ['pub', 'get'],
        workingDirectory: f.workspace.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  for (final extraComment in [false, true]) {
    test(
        'preserves ${extraComment ? 'edited' : 'tracked'} Melos-like overrides with CRLF',
        () async {
      final bridgeRepo = await remote('bridge');
      final repo = await remote('shared');
      File(p.join(repo.path, 'pubspec.yaml')).writeAsStringSync(
          'name: shared\nenvironment: {sdk: ^3.6.0}\nresolution: workspace\n');
      final source = '# melos_managed_dependency_overrides: bridge\n'
          'dependency_overrides:\n  bridge: {path: ../bridge}\n'
          '${extraComment ? '# keep my configuration\n' : ''}';
      File(p.join(repo.path, 'pubspec_overrides.yaml'))
          .writeAsStringSync(source);
      // Exercise Windows-style checkout conversion on every test platform.
      File(p.join(repo.path, '.gitattributes'))
          .writeAsStringSync('pubspec_overrides.yaml text eol=crlf\n');
      await f.commit(repo, 'Tracked override');
      final clone = await f.clone(repo);
      if (extraComment) {
        File(p.join(clone.path, '.git', 'info', 'exclude')).writeAsStringSync(
            'pubspec_overrides.yaml\n',
            mode: FileMode.append);
        await git(clone, ['rm', '--cached', 'pubspec_overrides.yaml']);
        await f.commit(clone, 'Untrack personal override');
      }
      app('dependencies:\n${f.dependency('shared', repo)}${f.dependency('bridge', bridgeRepo)}');
      final override = file('packages/shared/pubspec_overrides.yaml');
      expect(override.readAsStringSync(), contains('\r\n'));
      final before = override.readAsBytesSync();
      await expectLater(pull(), throwsStateError);
      expect(override.readAsBytesSync(), before);
      expect(file('pubspec.yaml').existsSync(), false);
    });
  }

  test('root overrides of a selected workspace member fail before checkout',
      () async {
    final repo = await remote('shared');
    app('dependencies:\n${f.dependency('shared', repo)}');
    file('pubspec_overrides.yaml').writeAsStringSync(
        'dependency_overrides:\n  shared: {path: packages/shared}\n');
    await expectLater(
        pull(),
        throwsA(isA<StateError>().having((error) => error.message, 'message',
            contains('Cannot override Pub workspace member'))));
    expect(f.clonePath('shared').existsSync(), false);
  });
  for (final staged in [false, true]) {
    test(
        staged
            ? 'preserves a consumer override staged but not committed'
            : 'preserves a committed consumer override in a repository above the workspace',
        () async {
      app('dependencies:\n  bridge: {path: ../../libraries/bridge}\n',
          resolution: true);
      final bridge = file('libraries/bridge/pubspec.yaml');
      bridge.parent.createSync(recursive: true);
      bridge.writeAsStringSync('name: bridge\nenvironment: {sdk: ^3.6.0}\n');
      final repository = staged ? f.consumer : f.root;
      await git(repository, ['init', '-b', 'main']);
      await f.commit(repository, 'Initial consumer');
      final override = file('apps/app/pubspec_overrides.yaml');
      const source = '# melos_managed_dependency_overrides: bridge\n'
          'dependency_overrides:\n  bridge: {path: ../../libraries/bridge}\n';
      override.writeAsStringSync(source);
      await git(repository,
          ['add', '--', p.relative(override.path, from: repository.path)]);
      if (!staged) await f.commit(repository, 'Track consumer overrides');
      final indexBefore = await git(repository, ['diff', '--cached']);
      await expectLater(
          pull(),
          throwsA(isA<StateError>().having(
              (error) => error.message,
              'member override conflict',
              contains('Cannot override Pub workspace member'))));
      expect(override.readAsStringSync(), source);
      expect(await git(repository, ['diff', '--cached']), indexBefore);
      expect(file('pubspec.yaml').existsSync(), false);
    });
  }
  test('mixed Melos files retain version pins after removing redundant paths',
      () async {
    app('dependencies:\n  bridge: {path: features/bridge}\n', resolution: true);
    final bridge = file('apps/app/features/bridge/pubspec.yaml');
    bridge.parent.createSync(recursive: true);
    bridge.writeAsStringSync(
        'name: bridge\nenvironment: {sdk: ^3.6.0}\nresolution: workspace\n');
    final override = file('apps/app/pubspec_overrides.yaml');
    override.writeAsStringSync(
        '# melos_managed_dependency_overrides: intl,bridge\n'
        'dependency_overrides:\n  intl: 0.19.0\n  bridge: {path: features/bridge}\n');
    await pull();
    expect(loadYaml(override.readAsStringSync())['dependency_overrides'],
        {'intl': '0.19.0'});
    expect(override.readAsStringSync(),
        startsWith('# melos_managed_dependency_overrides: intl\n'));
    final before = override.readAsStringSync();
    await pull();
    expect(override.readAsStringSync(), before);
  });

  Future<void> pinFixture(String first, String second) async {
    app('dependencies:\n  one: {path: features/one}\n  two: {path: features/two}\n',
        resolution: true);
    for (final name in ['one', 'two']) {
      final pubspec = file('apps/app/features/$name/pubspec.yaml');
      pubspec.parent.createSync(recursive: true);
      pubspec.writeAsStringSync(
          'name: $name\nenvironment: {sdk: ^3.6.0}\nresolution: workspace\n');
      file('apps/app/features/$name/pubspec_overrides.yaml').writeAsStringSync(
          '# melos_managed_dependency_overrides: intl\ndependency_overrides:\n'
          '  intl: ${name == 'one' ? first : second}\n');
    }
  }

  test('identical Melos pins are centralized once and survive repeated pulls',
      () async {
    await pinFixture('0.19.0', '0.19.0');
    await pull();
    expect(
        loadYaml(
            file('pubspec.yaml').readAsStringSync())['dependency_overrides'],
        {'intl': '0.19.0'});
    for (final name in ['one', 'two']) {
      expect(
          file('apps/app/features/$name/pubspec_overrides.yaml').existsSync(),
          false);
    }
    await pull();
    expect(
        loadYaml(
            file('pubspec.yaml').readAsStringSync())['dependency_overrides'],
        {'intl': '0.19.0'});
    app('', resolution: true);
    await pull();
    expect(
        loadYaml(
            file('pubspec.yaml').readAsStringSync())['dependency_overrides'],
        isNull);
    app('dependencies:\n  one: {path: features/one}\n', resolution: true);
    await pull();
    expect(
        loadYaml(
            file('pubspec.yaml').readAsStringSync())['dependency_overrides'],
        {'intl': '0.19.0'});
  });

  test('conflicting Melos pins fail without changing the files', () async {
    await pinFixture('0.19.0', '0.20.0');
    final before =
        file('apps/app/features/one/pubspec_overrides.yaml').readAsBytesSync();
    await expectLater(
        pull(),
        throwsA(isA<StateError>().having((e) => e.message, 'pin conflict',
            contains('Conflicting overrides for intl'))));
    expect(
        file('apps/app/features/one/pubspec_overrides.yaml').readAsBytesSync(),
        before);
    expect(file('pubspec.yaml').existsSync(), false);
  });

  test('duplicate pins in tracked override files require a manual fix',
      () async {
    await pinFixture('0.19.0', '0.19.0');
    await git(f.consumer, ['init', '-b', 'main']);
    await f.commit(f.consumer, 'User-owned overrides');
    await expectLater(
        pull(),
        throwsA(isA<StateError>().having((e) => e.message, 'protected pin',
            contains('protected configuration'))));
    expect(file('pubspec.yaml').existsSync(), false);
    expect(file('apps/app/features/one/pubspec_overrides.yaml').existsSync(),
        true);
  });

  test('centralized pins do not silently overwrite later user edits', () async {
    await pinFixture('0.19.0', '0.19.0');
    await pull();
    final override = file('apps/app/features/one/pubspec_overrides.yaml');
    override.writeAsStringSync('dependency_overrides: {intl: 0.20.0}\n');
    await expectLater(
        pull(),
        throwsA(isA<StateError>().having((e) => e.message, 'edited origin',
            contains('changed after centralizing intl'))));
    expect(
        override.readAsStringSync(), 'dependency_overrides: {intl: 0.20.0}\n');
  });
  test('identical non-member paths are consolidated relative to the root',
      () async {
    await pinFixture('0.19.0', '0.19.0');
    final external = file('libraries/shared_lib/pubspec.yaml');
    external.parent.createSync(recursive: true);
    external
        .writeAsStringSync('name: shared_lib\nenvironment: {sdk: ^3.6.0}\n');
    for (final name in ['one', 'two']) {
      file('apps/app/features/$name/pubspec_overrides.yaml').writeAsStringSync(
          '# melos_managed_dependency_overrides: shared_lib\n'
          'dependency_overrides:\n  shared_lib:\n'
          '    path: ${name == 'one' ? '../../../../libraries/shared_lib' : '../../../../libraries/./shared_lib'}\n');
    }
    await pull();
    final root = loadYaml(file('pubspec.yaml').readAsStringSync());
    expect(root['dependency_overrides'], {
      'shared_lib': {'path': 'libraries/shared_lib'}
    });
    expect(root['workspace'], isNot(contains('libraries/shared_lib')));
    await pull();
    expect(
        loadYaml(
            file('pubspec.yaml').readAsStringSync())['dependency_overrides'],
        {
          'shared_lib': {'path': 'libraries/shared_lib'}
        });
    final result = await Process.run(
        Platform.resolvedExecutable, ['pub', 'get'],
        workingDirectory: f.workspace.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('different local override targets are not consolidated', () async {
    await pinFixture('0.19.0', '0.19.0');
    for (final name in ['one', 'two']) {
      file('apps/app/features/$name/pubspec_overrides.yaml').writeAsStringSync(
          '# melos_managed_dependency_overrides: shared_lib\n'
          'dependency_overrides:\n  shared_lib: {path: ../../../../libraries/$name}\n');
    }
    await expectLater(
        pull(),
        throwsA(isA<StateError>().having(
            (e) => e.message,
            'different target conflict',
            contains('Conflicting overrides for shared_lib'))));
    expect(file('pubspec.yaml').existsSync(), false);
  });
  test('a later root override cannot hide centralized configuration', () async {
    await pinFixture('0.19.0', '0.19.0');
    await pull();
    file('pubspec_overrides.yaml')
        .writeAsStringSync('dependency_overrides: {}\n');
    await expectLater(
        pull(),
        throwsA(isA<StateError>().having(
            (e) => e.message,
            'root shadow conflict',
            contains('would hide the centralized intl override'))));
    expect(file('pubspec_overrides.yaml').readAsStringSync(),
        'dependency_overrides: {}\n');
  });
}
