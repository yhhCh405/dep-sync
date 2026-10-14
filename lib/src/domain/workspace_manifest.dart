/// Workspace search locations and package exclusions, loaded from the manifest.
///
/// Use `ManifestRepository` to validate user-provided YAML before constructing
/// this model. Directory paths are relative to the shared workspace root;
/// [ignorePackages] contains exact pubspec dependency names, not repository URLs.
/// The consumer pubspec, rather than this configuration, selects repositories.
class WorkspaceManifest {
  /// Creates configuration with `apps`/`packages` search roots and no exclusions.
  const WorkspaceManifest({
    this.searchRoots = const ['apps', 'packages'],
    this.defaultCloneRoot = 'packages',
    this.ignorePackages = const {},
  });

  /// Relative directories to search recursively for existing Git checkouts.
  final List<String> searchRoots;

  /// Relative parent for new clones; also searched for existing repositories.
  final String defaultCloneRoot;

  /// Exact dependency names excluded from both synchronization and ref pinning.
  final Set<String> ignorePackages;
}
