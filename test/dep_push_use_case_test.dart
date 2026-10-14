import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:dep_sync/src/domain/dep_push_use_case.dart';
import 'package:dep_sync/src/domain/options.dart';
import 'package:test/test.dart';
import 'support/fixture.dart';

void main() {
  late Fixture f;
  setUp(() => f = Fixture());
  tearDown(() => f.dispose());
  Future<void> push() =>
      DepPushUseCase().run(PushOptions(cwd: f.consumer.path));
  test('pins committed HEAD without rewriting SDK or unrelated declarations',
      () async {
    final remote = await f.remote('shared', packagePath: 'packages/shared');
    final clone = await f.clone(remote);
    f.pubspec(
        'dependencies:\n${f.dependency('shared', remote, path: 'packages/shared')}  collection: any\n');
    await push();
    expect(f.yaml['dependencies']['shared']['git']['ref'], await f.head(clone));
    expect(f.yaml['dependencies']['shared']['git']['path'], 'packages/shared');
    expect(f.yaml['dependencies']['collection'], 'any');
    expect(f.yaml['environment']['sdk'], '>=2.18.0 <3.0.0');
    expect(File(p.join(f.workspace.path, 'pubspec.yaml')).existsSync(), false);
  });
  test('missing dependency aborts the entire pubspec update', () async {
    final one = await f.remote('one');
    final two = await f.remote('two');
    await f.clone(one);
    f.pubspec(
        'dependencies:\n${f.dependency('one', one)}${f.dependency('two', two)}');
    final before = f.pubspecFile.readAsStringSync();
    await expectLater(push(), throwsStateError);
    expect(f.pubspecFile.readAsStringSync(), before);
  });
  test('ignored unresolved dependencies preserve their exact declarations',
      () async {
    final remote = await f.remote('shared');
    f.manifest('ignore_packages: [shared]');
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    final before = f.pubspecFile.readAsStringSync();
    await push();
    expect(f.pubspecFile.readAsStringSync(), before);
  });
  test('dirty dependency aborts without changing any refs', () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote);
    File(p.join(clone.path, 'mine')).writeAsStringSync('mine');
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    final before = f.pubspecFile.readAsStringSync();
    await expectLater(push(), throwsStateError);
    expect(f.pubspecFile.readAsStringSync(), before);
  });
  test('git shorthand gets a ref and retains the URL', () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote);
    f.pubspec(
        "dependencies:\n  shared:\n    git: '${remote.path.replaceAll('\\', '/')}'\n");
    await push();
    expect(f.yaml['dependencies']['shared']['git']['url'],
        remote.path.replaceAll('\\', '/'));
    expect(f.yaml['dependencies']['shared']['git']['ref'], await f.head(clone));
  });
  test('pins Git declarations in all three supported sections', () async {
    final remote = await f.remote('shared');
    final clone = await f.clone(remote);
    f.pubspec([
      for (final section in [
        'dependencies',
        'dev_dependencies',
        'dependency_overrides'
      ])
        '$section:\n${f.dependency('shared', remote)}'
    ].join('\n'));
    await push();
    for (final section in [
      'dependencies',
      'dev_dependencies',
      'dependency_overrides'
    ]) {
      expect(f.yaml[section]['shared']['git']['ref'], await f.head(clone));
    }
  });
  test('Git worktree checkouts are supported for pinning', () async {
    final remote = await f.remote('shared');
    final worktree = f.clonePath('worktree');
    worktree.parent.createSync(recursive: true);
    await git(remote, ['remote', 'add', 'origin', remote.path]);
    await git(remote, ['worktree', 'add', '--detach', worktree.path, 'HEAD']);
    f.pubspec('dependencies:\n${f.dependency('shared', remote)}');
    await push();
    expect(
        f.yaml['dependencies']['shared']['git']['ref'], await f.head(remote));
  });
}
