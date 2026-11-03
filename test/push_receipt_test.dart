import 'dart:io';

import 'package:dep_sync/src/domain/dep_push_use_case.dart';
import 'package:dep_sync/src/domain/git_dependency.dart';
import 'package:dep_sync/src/domain/ports/pubspec_store.dart';
import 'package:dep_sync/src/infrastructure/pubspec_repository.dart';
import 'package:dep_sync/src/domain/options.dart';
import 'package:dep_sync/src/infrastructure/push_receipt_repository.dart';
import 'package:dep_sync/src/version.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/fixture.dart';

void main() {
  late Fixture f;
  setUp(() => f = Fixture());
  tearDown(() => f.dispose());
  File receipt() => File(p.join(f.consumer.path, 'dep-sync.lock'));
  Future<void> push(DateTime time) =>
      DepPushUseCase(clock: () => time).run(PushOptions(cwd: f.consumer.path));

  test('writes the shell-compatible receipt beside the consumer pubspec',
      () async {
    final repo = await f.remote('shared');
    await f.clone(repo);
    f.pubspec('dependencies:\n${f.dependency('shared', repo)}');
    await push(DateTime.parse('2026-11-03T09:00:00+06:30'));
    final yaml = loadYaml(receipt().readAsStringSync());
    expect(yaml['lock_version'], 1);
    expect(yaml['last_dep_push']['completed_at_utc'], '2026-11-03T02:30:00Z');
    expect(yaml['last_dep_push']['tool_version'], depSyncVersion);
    expect(File(p.join(f.workspace.path, 'dep-sync.lock')).existsSync(), false);
  });

  test('refreshes the receipt even when every Git ref is already pinned',
      () async {
    final repo = await f.remote('shared');
    final clone = await f.clone(repo);
    f.pubspec(
        'dependencies:\n${f.dependency('shared', repo, ref: await f.head(clone))}');
    final before = f.pubspecFile.readAsStringSync();
    await push(DateTime.utc(2026, 11, 3, 1));
    final old = receipt().readAsStringSync();
    await push(DateTime.utc(2026, 11, 3, 2));
    expect(receipt().readAsStringSync(), isNot(old));
    expect(receipt().readAsStringSync(), contains('2026-11-03T02:00:00Z'));
    expect(f.pubspecFile.readAsStringSync(), before);
  });

  test('successful no-dependency run also creates a receipt', () async {
    await push(DateTime.utc(2026, 11, 3));
    expect(receipt().existsSync(), true);
  });

  test('validation failure preserves the previous receipt and pubspec',
      () async {
    final repo = await f.remote('missing');
    f.pubspec('dependencies:\n${f.dependency('missing', repo)}');
    receipt().writeAsStringSync('previous receipt');
    final before = f.pubspecFile.readAsStringSync();
    await expectLater(push(DateTime.utc(2026, 11, 3)), throwsStateError);
    expect(receipt().readAsStringSync(), 'previous receipt');
    expect(f.pubspecFile.readAsStringSync(), before);
  });

  test('invalid receipt destination aborts before any refs are saved',
      () async {
    final repo = await f.remote('shared');
    await f.clone(repo);
    f.pubspec('dependencies:\n${f.dependency('shared', repo)}');
    Directory(receipt().path).createSync();
    final before = f.pubspecFile.readAsStringSync();
    await expectLater(push(DateTime.utc(2026, 11, 3)), throwsStateError);
    expect(f.pubspecFile.readAsStringSync(), before);
  });

  test('receipt refuses concurrent edits and cleans staging files', () {
    receipt().writeAsStringSync('previous');
    final plan = const PushReceiptRepository().prepare(f.consumer,
        completedAt: DateTime.utc(2026, 11, 3), toolVersion: depSyncVersion);
    receipt().writeAsStringSync('concurrent edit');
    expect(plan.commit, throwsStateError);
    plan.dispose();
    expect(receipt().readAsStringSync(), 'concurrent edit');
    expect(
        f.consumer.listSync().where(
            (file) => p.basename(file.path).startsWith('.dep-sync-receipt-')),
        isEmpty);
  });

  test('pubspec persistence failure keeps the receipt and removes staging',
      () async {
    receipt().writeAsStringSync('previous receipt');
    final before = f.pubspecFile.readAsStringSync();
    await expectLater(
        DepPushUseCase(pubspecs: _FailingPubspecStore())
            .run(PushOptions(cwd: f.consumer.path)),
        throwsStateError);
    expect(receipt().readAsStringSync(), 'previous receipt');
    expect(f.pubspecFile.readAsStringSync(), before);
    expect(
        f.consumer.listSync().where(
            (file) => p.basename(file.path).startsWith('.dep-sync-receipt-')),
        isEmpty);
  });

  test('receipt does not follow a symlink', () async {
    if (Platform.isWindows) return;
    final external = File(p.join(f.root.path, 'external'))
      ..writeAsStringSync('untouched');
    Link(receipt().path).createSync(external.path);
    await expectLater(push(DateTime.utc(2026, 11, 3)), throwsStateError);
    expect(external.readAsStringSync(), 'untouched');
  });
}

class _FailingPubspecStore implements PubspecStore {
  @override
  List<GitDependency> readGitDependencies(File file,
          {Set<String> ignored = const {}}) =>
      const PubspecRepository().readGitDependencies(file, ignored: ignored);

  @override
  void updateGitRefs(File file, Map<GitDependency, String> refs,
      {required String original}) {
    throw StateError('Simulated pubspec save failure');
  }
}
