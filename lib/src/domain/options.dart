/// Inputs for a single dependency checkout synchronization.
///
/// Pass an instance to `DepPullUseCase.run`, for example
/// `PullOptions(cwd: '/workspace/apps/app', repoUpdate: true)`. Defaults preserve
/// local changes; destructive actions require an explicit [force] choice.
class PullOptions {
  /// Creates pull options; omitted [cwd] uses the process working directory.
  const PullOptions({
    this.repoUpdate = false,
    this.pullBranchLatest = false,
    this.force = false,
    this.fresh = false,
    this.verbose = false,
    this.fallbackBranch,
    this.cwd,
  });

  /// Fetch and use the origin tip when the declaration names a branch.
  final bool repoUpdate;

  /// Advance to the unique remote branch containing a declared commit or tag.
  final bool pullBranchLatest;

  /// Permit discarding tracked changes and untracked files. Combined with
  /// [fresh], also permit discarding ignored files and unpublished commits.
  final bool force;

  /// Prepare replacement clones before replacing existing managed checkouts.
  final bool fresh;
  final bool verbose;

  /// Remote branch to try only when the declared ref cannot be resolved.
  final String? fallbackBranch;
  final String? cwd;
}

/// Inputs for pinning a consumer's Git refs to local dependency HEAD commits.
///
/// Pass `PushOptions(cwd: '/workspace/apps/app')` to `DepPushUseCase.run`.
/// This operation edits the consumer pubspec; it never uploads Git commits.
class PushOptions {
  /// Creates pinning options; omitted [cwd] uses the current directory.
  const PushOptions({this.verbose = false, this.cwd});
  final bool verbose;
  final String? cwd;
}
