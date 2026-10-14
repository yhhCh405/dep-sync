/// Workspace locations and dependency names excluded from synchronization.
class WorkspaceManifest {
  const WorkspaceManifest({
    this.searchRoots = const ['apps', 'packages'],
    this.defaultCloneRoot = 'packages',
    this.ignorePackages = const {},
  });

  final List<String> searchRoots;
  final String defaultCloneRoot;
  final Set<String> ignorePackages;
}
