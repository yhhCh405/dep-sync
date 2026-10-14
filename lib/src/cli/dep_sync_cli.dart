import 'dart:io';
import 'package:args/command_runner.dart';
import '../domain/dep_pull_use_case.dart';
import '../domain/dep_push_use_case.dart';
import '../domain/options.dart';
import '../infrastructure/git_client.dart';

const packageVersion = '0.1.0';

Future<void> runDepSync(List<String> arguments) async {
  final runner = CommandRunner<int>('dep-sync',
      'Synchronize Git dependencies across Dart and Flutter repositories.')
    ..argParser.addFlag('version',
        abbr: 'v', negatable: false, help: 'Show version information.')
    ..addCommand(_PullCommand())
    ..addCommand(_PushCommand());
  try {
    final results = runner.parse(arguments);
    if (results.flag('version')) {
      stdout.writeln('dep-sync version $packageVersion');
      return;
    }
    exitCode = await runner.runCommand(results) ?? 0;
  } on UsageException catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  } on ProcessException catch (error) {
    stderr.writeln(
        '[x] Could not run ${error.executable}. Install Git and make it available on PATH. ${redact(error.message)}');
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln('[x] ${error.message}: ${error.path ?? ''}');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('[x] ${redact(error.message)}');
    exitCode = 65;
  } on StateError catch (error) {
    stderr.writeln('[x] ${redact(error.message)}');
    exitCode = 1;
  }
}

class _PullCommand extends Command<int> {
  _PullCommand() {
    argParser
      ..addFlag('repo-update',
          negatable: false,
          help: 'Fetch and use the remote tip for branch refs.')
      ..addFlag('pull-branch',
          aliases: ['pull-branch-latest'],
          negatable: false,
          help: 'Use the tip of the unique remote branch containing the ref.')
      ..addFlag('force',
          negatable: false,
          help:
              'Discard tracked changes and untracked files in managed dependencies.')
      ..addFlag('fresh',
          aliases: ['reclone'],
          negatable: false,
          help:
              'Replace managed clones only after replacement clones and refs are validated.')
      ..addOption('fallback-branch',
          help: 'Use this remote branch when a declared ref is missing.')
      ..addOption('cwd',
          help: 'Consumer package directory (defaults to current directory).')
      ..addFlag('verbose', negatable: false, help: 'Enable diagnostic output.');
  }
  @override
  String get name => 'pull';
  @override
  String get description =>
      'Clone and check out dependencies declared in the consumer pubspec.yaml.';
  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('Unexpected positional arguments.');
    }
    await DepPullUseCase().run(PullOptions(
      repoUpdate: argResults!.flag('repo-update'),
      pullBranchLatest: argResults!.flag('pull-branch'),
      force: argResults!.flag('force'),
      fresh: argResults!.flag('fresh'),
      verbose: argResults!.flag('verbose') || _envVerbose(),
      fallbackBranch: argResults!['fallback-branch'] as String?,
      cwd: argResults!['cwd'] as String?,
    ));
    return 0;
  }
}

class _PushCommand extends Command<int> {
  _PushCommand() {
    argParser
      ..addOption('cwd',
          help: 'Consumer package directory (defaults to current directory).')
      ..addFlag('verbose', negatable: false, help: 'Enable diagnostic output.');
  }
  @override
  String get name => 'push';
  @override
  String get description =>
      'Pin dependency refs to local HEAD commits. Does not run git push.';
  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('Unexpected positional arguments.');
    }
    await DepPushUseCase().run(PushOptions(
      verbose: argResults!.flag('verbose') || _envVerbose(),
      cwd: argResults!['cwd'] as String?,
    ));
    return 0;
  }
}

bool _envVerbose() => const {'1', 'true', 'yes', 'on'}
    .contains((Platform.environment['DEP_SYNC_VERBOSE'] ?? '').toLowerCase());
