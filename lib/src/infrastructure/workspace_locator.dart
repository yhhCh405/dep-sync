import 'dart:io';
import 'package:path/path.dart' as p;

/// Finds the shared workspace containing a consumer package.
///
/// Call [findWorkspaceRoot] with an existing consumer directory. The nearest
/// ancestor with `.dep-sync/manifest.yaml` owns its configuration; IDE workspace
/// files are not markers. Discovery reads the filesystem without modifying it.
class WorkspaceLocator {
  /// Creates a stateless workspace discovery helper.
  const WorkspaceLocator();

  /// Resolves [start] and walks upward to the nearest manifest marker.
  ///
  /// Returns the workspace directory, or throws if the start cannot be resolved
  /// or no ancestor contains a manifest.
  Directory findWorkspaceRoot(Directory start) {
    var current = Directory(start.resolveSymbolicLinksSync());
    while (true) {
      if (File(p.join(current.path, '.dep-sync', 'manifest.yaml'))
          .existsSync()) {
        return current;
      }
      final parent = current.parent;
      if (parent.path == current.path) {
        throw StateError(
            'Workspace not found. Create .dep-sync/manifest.yaml in the shared workspace root (workspace: {} enables defaults).');
      }
      current = parent;
    }
  }
}
