import 'dart:io';
import 'package:path/path.dart' as p;
import '../domain/workspace_manifest.dart';
import 'git_client.dart';
import 'git_url_normalizer.dart';
import 'manifest_repository.dart';

class RepositoryLocator {
  RepositoryLocator(this.git);
  final GitClient git;
  final normalizer = const GitUrlNormalizer();

  Directory safeDirectory(Directory workspace, String relative) {
    validateRelativePath(relative);
    var current = workspace;
    for (final part in p.posix.split(p.posix.normalize(relative))) {
      if (part == '.') continue;
      current = Directory(p.join(current.path, part));
      if (FileSystemEntity.typeSync(current.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError(
            'Symlink paths are not supported for checkout locations: ${current.path}');
      }
    }
    return current;
  }

  Future<Map<String, List<Directory>>> index(
      Directory workspace, WorkspaceManifest manifest) async {
    final repositories = <String, Directory>{};
    final visited = <String>{};
    void visit(Directory directory) {
      if (!visited.add(directory.path) || !directory.existsSync()) return;
      if (git.isRepository(directory)) repositories[directory.path] = directory;
      for (final entry in directory.listSync(followLinks: false)) {
        if (entry is! Directory) continue;
        final name = p.basename(entry.path);
        if (name.startsWith('.') || {'build', 'node_modules'}.contains(name)) {
          continue;
        }
        visit(entry);
      }
    }

    for (final relative in {
      ...manifest.searchRoots,
      manifest.defaultCloneRoot
    }) {
      visit(safeDirectory(workspace, relative));
    }
    final index = <String, List<Directory>>{};
    for (final repository in repositories.values) {
      final url = await git.originUrl(repository);
      if (url != null) {
        index
            .putIfAbsent(normalizer.normalize(url, relativeTo: repository.path),
                () => [])
            .add(repository);
      }
    }
    return index;
  }

  Directory? find(Map<String, List<Directory>> index, String identity) {
    final matches = index[identity] ?? [];
    if (matches.length > 1) {
      throw StateError(
          'Multiple checkouts match a dependency: ${matches.map((repo) => repo.path).join(', ')}. Narrow workspace.search_roots or move the extra clone.');
    }
    return matches.isEmpty ? null : matches.single;
  }

  void protectConsumer(Directory repository, Directory consumer) {
    if (p.equals(repository.path, consumer.path) ||
        p.isWithin(repository.path, consumer.path)) {
      throw StateError(
          'Refusing to synchronize the repository containing the consumer: ${repository.path}');
    }
  }

  void protectNewTarget(Directory target) {
    if (FileSystemEntity.typeSync(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError(
          'Clone destination already exists: ${target.path}. Move it or clone the dependency under a unique name in a search root.');
    }
  }

  void protectFresh(Directory repository) {
    if (File(p.join(repository.path, '.git')).existsSync()) {
      throw StateError(
          '--fresh is not supported for Git worktrees or submodules: ${repository.path}');
    }
    for (final entry
        in repository.listSync(recursive: true, followLinks: false)) {
      if (p.basename(entry.path) == '.git' &&
          p.dirname(entry.path) != repository.path) {
        throw StateError(
            '--fresh would remove a nested repository: ${entry.path}');
      }
    }
  }
}
