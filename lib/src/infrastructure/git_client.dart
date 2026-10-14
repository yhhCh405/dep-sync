import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/ports/git_operations.dart';
import 'process_runner.dart';

/// Command-line Git implementation of [GitOperations].
///
/// Use the typed repository methods for synchronization, or inject a
/// [ProcessExecutor] to control process execution in tests. Each command runs in
/// its repository directory with hooks and the `ext` transport disabled. This
/// adapter performs Git operations; use cases own sequencing and safety checks.
class GitClient implements GitOperations {
  /// Uses [ProcessRunner] by default; accepts any [ProcessExecutor] implementation.
  GitClient({ProcessExecutor? runner})
      : _runner = runner ?? const ProcessRunner();
  final ProcessExecutor _runner;

  /// Runs a Git command in [repo] with the adapter's common process settings.
  ///
  /// Returns nonzero results unchanged so lookup methods can represent absence.
  /// Call [require] for operations whose failure must abort synchronization.
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

  /// Runs Git and returns trimmed stdout, or throws on a nonzero exit.
  ///
  /// The failure message includes the working directory and redacted Git stderr.
  /// Startup failures from the process executor propagate unchanged.
  Future<String> require(Directory repo, List<String> arguments) async {
    final result = await run(repo, arguments);
    if (!result.succeeded) {
      throw StateError(
          'Git ${arguments.first} failed in ${repo.path}: ${redact(result.stderr.trim())}');
    }
    return result.stdout.trim();
  }

  /// Clones into an unused [target]; its parent must exist and callers own cleanup.
  @override
  Future<void> clone(String url, Directory target) async {
    await require(target.parent, ['clone', '--', url, target.path]);
  }

  /// Checks for a `.git` marker directory or file without following that marker.
  @override
  bool isRepository(Directory directory) =>
      FileSystemEntity.typeSync(p.join(directory.path, '.git'),
          followLinks: false) !=
      FileSystemEntityType.notFound;

  /// Reads `remote.origin.url`, returning null for a missing or unreadable value.
  @override
  Future<String?> originUrl(Directory directory) async {
    final result =
        await run(directory, ['config', '--get', 'remote.origin.url']);
    return result.succeeded && result.stdout.trim().isNotEmpty
        ? result.stdout.trim()
        : null;
  }

  /// Reads and verifies HEAD, throwing if the repository has no resolvable commit.
  @override
  Future<String> head(Directory directory) =>
      require(directory, ['rev-parse', '--verify', 'HEAD']);

  /// Checks porcelain status; include ignored files before replacing a whole clone.
  @override
  Future<bool> hasLocalChanges(Directory directory,
          {bool includeIgnored = false}) async =>
      (await require(directory, [
        'status',
        '--porcelain',
        '--untracked-files=all',
        if (includeIgnored) '--ignored'
      ]))
          .isNotEmpty;

  /// Checks HEAD and all refs, including stashes, against locally recorded origin refs.
  @override
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

  /// Refuses to abandon a detached commit that no branch, tag, or remote ref retains.
  @override
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

  /// Refreshes all origin branch refs and prunes deleted branches; leaves HEAD unchanged.
  @override
  Future<void> fetch(Directory directory) async {
    await require(directory,
        ['fetch', '--prune', 'origin', '+refs/heads/*:refs/remotes/origin/*']);
  }

  /// Resolves a local revision to a commit, returning null on Git lookup failure.
  @override
  Future<String?> resolve(Directory directory, String ref) async {
    final result = await run(directory,
        ['rev-parse', '--verify', '--end-of-options', '$ref^{commit}']);
    return result.succeeded ? result.stdout.trim() : null;
  }

  /// Uses local branch, tag, origin branch, then revision lookup; empty refs use origin HEAD.
  @override
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

  /// Selects the unique containing origin branch, throwing if absent or ambiguous.
  @override
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

  /// Reads committed file content without checkout, returning null on Git read failure.
  @override
  Future<String?> readFileAtCommit(
      Directory directory, String hash, String path) async {
    final result = await run(directory, ['show', '$hash:$path']);
    return result.succeeded ? result.stdout : null;
  }

  /// Checks out a validated commit with detached HEAD and ignored-file protection.
  ///
  /// [force] first resets tracked edits and cleans untracked files. The caller
  /// must authorize this and validate [hash] before invoking the destructive path.
  @override
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

/// Masks user information embedded in HTTP(S) and SSH URLs in error messages.
///
/// Use before displaying Git errors. This is targeted URL redaction, not a general
/// secret detector; callers should avoid putting credentials in command arguments.
String redact(String text) =>
    text.replaceAll(RegExp(r'(https?|ssh)://[^/\s@]+@'), '***://[redacted]@');
