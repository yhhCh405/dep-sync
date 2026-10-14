import 'dart:io';

/// Git operations required by dependency synchronization and discovery.
///
/// Implement this contract to substitute a Git backend in the pull/push use
/// cases. Production uses `GitClient`; orchestration depends on repository
/// operations rather than process output or Git command-line arguments.
abstract interface class GitOperations {
  /// Clones [url] into [target], whose parent must already exist.
  ///
  /// The destination must be unused. A failed clone throws; callers own cleanup
  /// of partially created destinations and should clone into a staging folder.
  Future<void> clone(String url, Directory target);

  /// Whether [directory] has a `.git` marker, including worktree marker files.
  ///
  /// This is a discovery check, not proof that the repository is healthy.
  bool isRepository(Directory directory);

  /// Returns the configured origin URL, or null if it cannot be read.
  Future<String?> originUrl(Directory directory);

  /// Returns the current HEAD commit hash, throwing if HEAD cannot be read.
  Future<String> head(Directory directory);

  /// Detects tracked changes and untracked files, optionally including ignored
  /// files before replacement of an entire clone. Status failures must throw.
  Future<bool> hasLocalChanges(Directory directory,
      {bool includeIgnored = false});

  /// Detects commits reachable from HEAD or local refs, including stashes, that
  /// are not reachable from locally recorded origin refs.
  ///
  /// This does not contact the remote; callers must account for stale refs.
  Future<bool> hasUnpushedCommits(Directory directory);

  /// Throws if moving to [target] would abandon a detached HEAD that no branch,
  /// tag, or remote-tracking ref retains. Does not alter the checkout.
  Future<void> protectDetachedHead(Directory directory, String target);

  /// Fetches origin branches and prunes stale tracking refs without checkout.
  Future<void> fetch(Directory directory);

  /// Resolves [ref] to a commit hash, or null if Git cannot resolve it locally.
  Future<String?> resolve(Directory directory, String ref);

  /// Resolves a declaration using local branch, tag, remote branch, then Git
  /// revision lookup. An empty [ref] uses the recorded origin HEAD.
  Future<String?> resolveDeclared(Directory directory, String ref);

  /// Returns the tip of the unique origin branch containing [hash].
  ///
  /// Throws for zero or multiple matches. Fetch first for current remote refs.
  Future<String> containingBranchTip(Directory directory, String hash);

  /// Reads [path] relative to the repository tree at [hash], without checkout.
  /// Returns null if Git cannot read that object; preserves file content.
  Future<String?> readFileAtCommit(
      Directory directory, String hash, String path);

  /// Checks out [hash] as detached HEAD, preserving existing local branches.
  ///
  /// With [force], resets tracked changes and removes untracked files first.
  /// Callers must validate the destination commit before permitting destruction.
  /// Ignored files remain protected against checkout collisions.
  Future<void> checkout(Directory directory, String hash,
      {required bool force});
}
