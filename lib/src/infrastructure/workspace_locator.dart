import 'dart:io';
import 'package:path/path.dart' as p;

class WorkspaceLocator {
  const WorkspaceLocator();

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
