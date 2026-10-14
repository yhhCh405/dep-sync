import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:dep_sync/src/domain/dep_pull_use_case.dart';
import 'package:dep_sync/src/domain/options.dart';
import 'package:test/test.dart';
import 'support/fixture.dart';

void main() {
  late Fixture f;
  setUp(() => f = Fixture());
  tearDown(() => f.dispose());
  Future<void> pull(
          {bool force = false,
          bool fresh = false,
          bool update = false,
          bool branch = false,
          String? fallback}) =>
      DepPullUseCase().run(PullOptions(
          cwd: f.consumer.path,
          force: force,
          fresh: fresh,
          repoUpdate: update,
          pullBranchLatest: branch,
          fallbackBranch: fallback));

  test(
      'clones direct dependencies without touching SDK, workspace or override files',
      () async {
    final remote = await f.remote('shared');
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    final before = f.pubspecFile.readAsStringSync();
    final rootPubspec = File(p.join(f.workspace.path, 'pubspec.yaml'))
      ..writeAsStringSync('name: existing_root\n');
    final overrides = File(p.join(f.consumer.path, 'pubspec_overrides.yaml'))
      ..writeAsStringSync('dependency_overrides: {custom: any}\n');
    await pull();
    expect(await f.head(f.clonePath('shared')), await f.head(remote));
    expect(f.pubspecFile.readAsStringSync(), before);
    expect(rootPubspec.readAsStringSync(), 'name: existing_root\n');
    expect(
        overrides.readAsStringSync(), 'dependency_overrides: {custom: any}\n');
    expect(
        File(p.join(f.clonePath('shared').path, 'pubspec.yaml'))
            .readAsStringSync(),
        contains('>=2.18.0 <3.0.0'));
    expect(
        File(p.join(f.clonePath('shared').path, 'pubspec_overrides.yaml'))
            .existsSync(),
        false);
  });
  test('consumer at workspace root is never overwritten', () async {
    f.consumer = f.workspace;
    f.pubspec('');
    final before = f.pubspecFile.readAsStringSync();
    await pull();
    expect(f.pubspecFile.readAsStringSync(), before);
  });
  test('no dependencies leaves previous local clones untouched', () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote);
    await pull();
    expect(clone.existsSync(), true);
  });
  test('ignored package is not cloned, even with force and fresh', () async {
    final remote = await f.remote('shared');
    f.manifest('ignore_packages: [shared]');
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await pull(force: true, fresh: true);
    expect(f.clonePath('shared').existsSync(), false);
  });
  test('ignored dirty clone and its overrides remain untouched', () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote);
    final file = File(p.join(clone.path, 'pubspec_overrides.yaml'))
      ..writeAsStringSync('mine');
    f.manifest('ignore_packages: [shared]');
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await pull(force: true, fresh: true);
    expect(file.readAsStringSync(), 'mine');
  });
  test('ignored packages sharing a repository fail before changes', () async {
    final remote = await f.remote('shared');
    f.manifest('ignore_packages: [ignored]');
    f.pubspec(
        'dependencies:\n${f.dependency('shared', remote)}${f.dependency('ignored', remote, path: 'sub')}');
    await expectLater(pull(), throwsStateError);
    expect(f.clonePath('shared').existsSync(), false);
  });
  test('URL aliases cannot bypass an ignored repository', () async {
    final remote = await f.remote('shared');
    f.manifest('ignore_packages: [ignored]');
    f.pubspec(
        'dependencies:\n${f.dependency('shared', remote)}  ignored:\n    git: ${Uri.directory(remote.path)}\n');
    await expectLater(pull(), throwsStateError);
  });
  test('conflicting refs from one repository fail before clone', () async {
    final remote = await f.remote('shared');
    f.pubspec(
        'dependencies:\n${f.dependency('shared', remote)}${f.dependency('second', remote, ref: 'other')}');
    await expectLater(pull(), throwsStateError);
    expect(f.clonePath('shared').existsSync(), false);
  });
  test('a repository with multiple packages is cloned once', () async {
    final remote =
        await f.remote('mono', packageName: 'one', packagePath: 'packages/one');
    final second = File(p.join(remote.path, 'packages', 'two', 'pubspec.yaml'));
    second.parent.createSync(recursive: true);
    second.writeAsStringSync('name: two\n');
    await f.commit(remote, 'second package');
    f.pubspec(
        'dependencies:\n${f.dependency('one', remote, path: 'packages/one')}${f.dependency('two', remote, path: 'packages/two')}');
    await pull();
    expect(await f.head(f.clonePath('mono')), await f.head(remote));
  });
  test('finds existing clones by origin regardless of folder name', () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote, name: 'custom-location');
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await pull();
    expect(await f.head(clone), await f.head(remote));
    expect(f.clonePath('shared').existsSync(), false);
  });
  test('ambiguous clones are rejected', () async {
    final remote = await f.remote('shared');
    await f.clone(remote, name: 'one');
    await f.clone(remote, name: 'two');
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await expectLater(pull(), throwsStateError);
  });
  test('an occupied destination is preserved', () async {
    final remote = await f.remote('shared');
    final clone = f.clonePath('shared')..createSync(recursive: true);
    final sentinel = File(p.join(clone.path, 'mine'))
      ..writeAsStringSync('mine');
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await expectLater(pull(), throwsStateError);
    expect(sentinel.readAsStringSync(), 'mine');
  });
  test('dirty repositories are protected without force', () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote);
    final file = File(p.join(clone.path, 'pubspec.yaml'));
    file.writeAsStringSync('${file.readAsStringSync()}# local edit\n');
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await expectLater(pull(), throwsStateError);
    expect(file.readAsStringSync(), contains('# local edit'));
    await pull(force: true);
    expect(file.readAsStringSync(), isNot(contains('# local edit')));
  });
  test('invalid ref does not discard dirty files even with force', () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote);
    final file = File(p.join(clone.path, 'mine'))..writeAsStringSync('mine');
    f.pubspec(
        'dependencies:\n${f.dependency('shared', remote, ref: 'does-not-exist')}');
    await expectLater(pull(force: true), throwsStateError);
    expect(file.readAsStringSync(), 'mine');
  });
  test('failed fresh clone leaves the original checkout intact', () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote);
    final old = await f.head(clone);
    f.pubspec(
        'dependencies:\n${f.dependency('shared', remote, ref: 'missing')}');
    await expectLater(pull(fresh: true), throwsStateError);
    expect(await f.head(clone), old);
    expect(
        clone.parent.listSync().where(
            (entry) => p.basename(entry.path).startsWith('.dep-sync-clone-')),
        isEmpty);
  });
  test('fresh protects local commits and ignored files', () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote);
    File(p.join(clone.path, 'mine')).writeAsStringSync('local commit');
    await f.commit(clone, 'unpushed');
    final old = await f.head(clone);
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await expectLater(pull(fresh: true), throwsStateError);
    expect(await f.head(clone), old);
    await pull(fresh: true, force: true);
    expect(await f.head(clone), await f.head(remote));
  });
  test('all refs are validated before moving any existing checkout', () async {
    final one = await f.remote('one');
    final two = await f.remote('two');
    final clone = await f.clone(one);
    final old = await f.head(clone);
    File(p.join(one.path, 'new')).writeAsStringSync('new');
    await f.commit(one, 'new');
    f.pubspec(
        'dependencies:\n${f.dependency('one', one, ref: await f.head(one))}${f.dependency('two', two, ref: 'missing')}');
    await expectLater(pull(), throwsStateError);
    expect(await f.head(clone), old);
    expect(f.clonePath('two').existsSync(), false);
  });
  test('repo-update moves to remote tip without rewriting local branches',
      () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote);
    final old = await f.head(clone);
    File(p.join(remote.path, 'new')).writeAsStringSync('new');
    await f.commit(remote, 'new');
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await pull();
    expect(await f.head(clone), old);
    await pull(update: true);
    expect(await f.head(clone), await f.head(remote));
    expect(await git(clone, ['rev-parse', 'refs/heads/main']), old);
  });
  test('fallback checks out a remote branch when a ref is missing', () async {
    final remote = await f.remote('shared');
    f.pubspec(
        'dependencies:\n${f.dependency('shared', remote, ref: 'missing')}');
    await pull(fallback: 'main');
    expect(await f.head(f.clonePath('shared')), await f.head(remote));
  });
  test('missing ref uses remote HEAD', () async {
    final remote = await f.remote('shared');
    f.pubspec(
        "dependencies:\n  shared:\n    git: '${remote.path.replaceAll('\\', '/')}'\n");
    await pull();
    expect(await f.head(f.clonePath('shared')), await f.head(remote));
  });
  test('wrong package path aborts without installing a clone', () async {
    final remote = await f.remote('shared');
    f.pubspec(
        'dependencies:\n${f.dependency('shared', remote, path: 'missing')}');
    await expectLater(pull(), throwsStateError);
    expect(f.clonePath('shared').existsSync(), false);
  });
  test('symlink clone root cannot escape the workspace', () async {
    final remote = await f.remote('shared');
    final outside = Directory(p.join(f.root.path, 'outside'))..createSync();
    Link(p.join(f.workspace.path, 'packages')).createSync(outside.path);
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await expectLater(pull(), throwsStateError);
    expect(outside.listSync(), isEmpty);
  },
      skip: Platform.isWindows
          ? 'Creating symlinks requires Windows developer mode.'
          : false);
  test('consumer repository is protected even with force and fresh', () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote);
    f.consumer = clone;
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await expectLater(pull(force: true, fresh: true), throwsStateError);
    expect(clone.existsSync(), true);
  });
  test('fresh protects ignored files without force', () async {
    final remote = await f.remote('shared');
    File(p.join(remote.path, '.gitignore')).writeAsStringSync('private.txt\n');
    await f.commit(remote, 'ignore private file');
    final clone = await f.clone(remote);
    final private = File(p.join(clone.path, 'private.txt'))
      ..writeAsStringSync('keep');
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await expectLater(pull(fresh: true), throwsStateError);
    expect(private.readAsStringSync(), 'keep');
  });
  test('fresh protects stashed changes', () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote);
    File(p.join(clone.path, 'pubspec.yaml'))
        .writeAsStringSync('name: shared\n# stashed work\n');
    await git(clone, [
      '-c',
      'user.name=Test',
      '-c',
      'user.email=test@example.com',
      'stash',
      'push'
    ]);
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await expectLater(pull(fresh: true), throwsStateError);
    expect(await git(clone, ['stash', 'list']), isNotEmpty);
  });
  test('unreferenced detached commits are protected', () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote);
    await git(clone, ['checkout', '--detach']);
    File(p.join(clone.path, 'mine')).writeAsStringSync('unreferenced commit');
    await f.commit(clone, 'detached work');
    final old = await f.head(clone);
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await expectLater(pull(), throwsStateError);
    expect(await f.head(clone), old);
  });
  test('same basename from different repositories cannot overwrite a clone',
      () async {
    final first = await f.remote('one/shared', packageName: 'first');
    final second = await f.remote('two/shared', packageName: 'second');
    f.pubspec(
        'dependencies:\n${f.dependency('first', first)}${f.dependency('second', second)}');
    await expectLater(pull(), throwsStateError);
    expect(f.clonePath('shared').existsSync(), false);
  });
  test('pull-branch advances a pinned commit to the unique remote tip',
      () async {
    final remote = await f.remote('shared');
    final old = await f.head(remote);
    File(p.join(remote.path, 'new')).writeAsStringSync('new');
    await f.commit(remote, 'new');
    f.pubspec('dependencies:\n${f.dependency('shared', remote, ref: old)}');
    await pull(branch: true);
    expect(await f.head(f.clonePath('shared')), await f.head(remote));
  });
  test('pull-branch rejects ambiguous branch matches', () async {
    final remote = await f.remote('shared');
    final old = await f.head(remote);
    await git(remote, ['branch', 'other']);
    f.pubspec('dependencies:\n${f.dependency('shared', remote, ref: old)}');
    await expectLater(pull(branch: true), throwsStateError);
    expect(f.clonePath('shared').existsSync(), false);
  });
  test('fresh refuses worktrees even with force', () async {
    final remote = await f.remote('shared');
    await git(remote, ['remote', 'add', 'origin', remote.path]);
    final worktree = f.clonePath('shared');
    worktree.parent.createSync(recursive: true);
    await git(remote, ['worktree', 'add', '--detach', worktree.path, 'HEAD']);
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await expectLater(pull(force: true, fresh: true), throwsStateError);
    expect(await f.head(worktree), await f.head(remote));
  });
}
