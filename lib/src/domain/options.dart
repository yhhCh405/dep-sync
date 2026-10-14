class PullOptions {
  const PullOptions({
    this.repoUpdate = false,
    this.pullBranchLatest = false,
    this.force = false,
    this.fresh = false,
    this.verbose = false,
    this.fallbackBranch,
    this.cwd,
  });
  final bool repoUpdate;
  final bool pullBranchLatest;
  final bool force;
  final bool fresh;
  final bool verbose;
  final String? fallbackBranch;
  final String? cwd;
}

class PushOptions {
  const PushOptions({this.verbose = false, this.cwd});
  final bool verbose;
  final String? cwd;
}
