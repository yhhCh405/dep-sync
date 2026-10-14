import 'dart:io';

import 'package:dep_sync/src/domain/dep_pull_use_case.dart';
import 'package:dep_sync/src/domain/dep_push_use_case.dart';
import 'package:dep_sync/src/domain/git_dependency.dart';
import 'package:dep_sync/src/domain/options.dart';
import 'package:dep_sync/src/domain/ports/pubspec_store.dart';
import 'package:dep_sync/src/infrastructure/git_client.dart';
import 'package:dep_sync/src/infrastructure/process_runner.dart';
import 'package:dep_sync/src/infrastructure/pubspec_repository.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture.dart';

/// Verifies substituted adapters preserve orchestration safety guarantees.
void main() {
  late Fixture fixture;
  setUp(() => fixture = Fixture());
  tearDown(() => fixture.dispose());

  test('a failed fetch cannot discard local work even with force', () async {
    final remote = await fixture.remote('shared');
    final clone = await fixture.clone(remote);
    final before = await fixture.head(clone);
    final localFile = File(p.join(clone.path, 'local.txt'))
      ..writeAsStringSync('uncommitted work');
    fixture.pubspec('dependencies:\n${fixture.dependency('shared', remote)}');

    final useCase =
        DepPullUseCase(git: GitClient(runner: _FailingFetchRunner()));
    await expectLater(
      useCase.run(PullOptions(
        cwd: fixture.consumer.path,
        force: true,
        repoUpdate: true,
      )),
      throwsA(isA<StateError>().having((error) => error.message,
          'failure message', contains('remote unavailable'))),
    );

    expect(await fixture.head(clone), before);
    expect(localFile.readAsStringSync(), 'uncommitted work');
  });

  test('injected pubspec store is called only after every dependency resolves',
      () async {
    final one = await fixture.remote('one');
    final two = await fixture.remote('two');
    await fixture.clone(one);
    fixture.pubspec('dependencies:\n'
        '${fixture.dependency('one', one)}${fixture.dependency('two', two)}');
    final original = fixture.pubspecFile.readAsStringSync();
    final store = _RecordingPubspecStore();
    final useCase = DepPushUseCase(pubspecs: store);

    await expectLater(
      useCase.run(PushOptions(cwd: fixture.consumer.path)),
      throwsStateError,
    );
    expect(store.reads, 1);
    expect(store.writes, 0);
    expect(fixture.pubspecFile.readAsStringSync(), original);

    await fixture.clone(two);
    await useCase.run(PushOptions(cwd: fixture.consumer.path));
    expect(store.reads, 2);
    expect(store.writes, 1);
    expect(fixture.yaml['dependencies']['one']['git']['ref'],
        await fixture.head(one));
    expect(fixture.yaml['dependencies']['two']['git']['ref'],
        await fixture.head(two));
  });
}

/// Injects a network failure while allowing real Git discovery and status checks.
///
/// Supply to `GitClient(runner: ...)` to test pre-checkout failure behavior without
/// relying on an external remote or timing-sensitive network conditions.
class _FailingFetchRunner implements ProcessExecutor {
  /// Returns a failed result for fetch; delegates other commands to real processes.
  @override
  Future<CommandResult> run(String executable, List<String> arguments,
      {String? workingDirectory, Map<String, String>? environment}) async {
    if (executable == 'git' && arguments.contains('fetch')) {
      return const CommandResult(
          exitCode: 128, stdout: '', stderr: 'remote unavailable');
    }
    return const ProcessRunner().run(executable, arguments,
        workingDirectory: workingDirectory, environment: environment);
  }
}

/// Observes persistence calls while retaining real YAML parsing and atomic writes.
///
/// Inject into the push use case to verify that validation failure prevents any
/// save request and that successful pinning uses one complete batch.
class _RecordingPubspecStore implements PubspecStore {
  int reads = 0;
  int writes = 0;
  final _delegate = const PubspecRepository();

  /// Counts declaration reads and preserves the ignored-package parsing contract.
  @override
  List<GitDependency> readGitDependencies(File file,
      {Set<String> ignored = const {}}) {
    reads++;
    return _delegate.readGitDependencies(file, ignored: ignored);
  }

  /// Counts complete save requests and delegates persistence without alteration.
  @override
  void updateGitRefs(File file, Map<GitDependency, String> refs,
      {required String original}) {
    writes++;
    _delegate.updateGitRefs(file, refs, original: original);
  }
}
