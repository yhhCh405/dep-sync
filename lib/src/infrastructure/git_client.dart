import 'dart:io';
import 'package:path/path.dart' as p;
import 'process_runner.dart';

class GitClient {
  GitClient({ProcessRunner? runner})
      : _runner = runner ?? const ProcessRunner();
  final ProcessRunner _runner;

  Future<CommandResult> run(Directory repo, List<String> arguments) =>
      _runner.run(
        'git',
        [
          '-c',
          'core.hooksPath=${Platform.isWindows ? 'NUL' : '/dev/null'}',
          '-c',
          'protocol.ext.allow=never',
          ...arguments
        ],
        workingDirectory: repo.path,
      );

  Future<String> require(Directory repo, List<String> arguments) async {
    final result = await run(repo, arguments);
    if (!result.succeeded) {
      throw StateError(
          'Git ${arguments.first} failed in ${repo.path}: ${redact(result.stderr.trim())}');
    }
    return result.stdout.trim();
  }

  Future<void> clone(String url, Directory target) async {
    await require(target.parent, ['clone', '--', url, target.path]);
  }

  bool isRepository(Directory directory) =>
      FileSystemEntity.typeSync(p.join(directory.path, '.git'),
          followLinks: false) !=
      FileSystemEntityType.notFound;

  Future<String?> originUrl(Directory directory) async {
    final result =
        await run(directory, ['config', '--get', 'remote.origin.url']);
    return result.succeeded && result.stdout.trim().isNotEmpty
        ? result.stdout.trim()
        : null;
  }

  Future<String> head(Directory directory) =>
      require(directory, ['rev-parse', '--verify', 'HEAD']);

  Future<bool> hasLocalChanges(Directory directory,
          {bool includeIgnored = false}) async =>
      (await require(directory, [
        'status',
        '--porcelain',
        '--untracked-files=all',
        if (includeIgnored) '--ignored'
      ]))
          .isNotEmpty;

  Future<bool> hasUnpushedCommits(Directory directory) async =>
      (await require(directory, [
        'rev-list',
        '--max-count=1',
        'HEAD',
        '--all',
        '--not',
        '--remotes=origin'
      ]))
          .isNotEmpty;

  Future<void> protectDetachedHead(Directory directory, String target) async {
    final current = await head(directory);
    if (current == target) return;
    final branch = await run(directory, ['symbolic-ref', '-q', 'HEAD']);
    if (branch.succeeded) return;
    final retained = await require(directory, [
      'for-each-ref',
      '--format=%(refname)',
      '--contains',
      current,
      'refs/heads',
      'refs/tags',
      'refs/remotes'
    ]);
    if (retained.isEmpty) {
      throw StateError(
          'Unreferenced detached HEAD in ${directory.path}. Create a branch to retain your commits before pulling (or use --force).');
    }
  }

  Future<void> fetch(Directory directory) async {
    await require(directory,
        ['fetch', '--prune', 'origin', '+refs/heads/*:refs/remotes/origin/*']);
  }

  Future<String?> resolve(Directory directory, String ref) async {
    final result = await run(directory,
        ['rev-parse', '--verify', '--end-of-options', '$ref^{commit}']);
    return result.succeeded ? result.stdout.trim() : null;
  }

  Future<String?> resolveDeclared(Directory directory, String ref) async {
    if (ref.isEmpty) return resolve(directory, 'refs/remotes/origin/HEAD');
    for (final candidate in [
      'refs/heads/$ref',
      'refs/tags/$ref',
      'refs/remotes/origin/$ref',
      ref
    ]) {
      final hash = await resolve(directory, candidate);
      if (hash != null) return hash;
    }
    return null;
  }

  Future<String> containingBranchTip(Directory directory, String hash) async {
    final output = await require(directory, [
      'for-each-ref',
      '--format=%(refname)',
      '--contains',
      hash,
      'refs/remotes/origin'
    ]);
    final branches = output
        .split('\n')
        .where((line) => line.isNotEmpty && line != 'refs/remotes/origin/HEAD')
        .toList();
    if (branches.length != 1) {
      throw StateError(
          '--pull-branch requires exactly one containing remote branch; found ${branches.length}. Use an explicit branch ref with --repo-update.');
    }
    return (await resolve(directory, branches.single))!;
  }

  Future<void> checkout(Directory directory, String hash,
      {required bool force}) async {
    if (force) {
      await require(directory, ['reset', '--hard', 'HEAD']);
      await require(directory, ['clean', '-fd']);
    }
    // --no-overwrite-ignore protects files that Git would otherwise silently replace.
    await require(directory,
        ['checkout', '--detach', '--no-overwrite-ignore', hash, '--']);
  }
}

String redact(String text) =>
    text.replaceAll(RegExp(r'(https?|ssh)://[^/\s@]+@'), '***://[redacted]@');
