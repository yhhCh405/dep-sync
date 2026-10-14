import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/ports/git_operations.dart';
import '../domain/workspace_manifest.dart';
import 'git_url_normalizer.dart';
import 'manifest_repository.dart';

/// Discovers dependency checkouts and validates filesystem destinations.
///
/// Construct with the operation's [GitOperations], call [index] once, then [find]
/// using each normalized repository identity. Call the appropriate protection
/// methods before cloning, checkout, or replacement; discovery itself is read-only.
class RepositoryLocator {
  /// Uses [git] to inspect repository markers and origin URLs.
  RepositoryLocator(this.git);
  final GitOperations git;
  final normalizer = const GitUrlNormalizer();

  /// Builds a workspace-relative directory after lexical and symlink checks.
  ///
  /// The path need not exist yet. This method does not create directories.
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

  /// Indexes origins under configured search roots and the default clone root.
  ///
  /// Skips symlinks, hidden children, build output, and node_modules. Retains all
  /// matches for each identity so [find] can reject ambiguity rather than guess.
  Future<Map<String, List<Directory>>> index(
      Directory workspace, WorkspaceManifest manifest) async {
    final repositories = <String, Directory>{};
    final visited = <String>{};

    /// Recurses through searchable directories once, recording Git markers.
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

  /// Selects the sole checkout for a normalized [identity].
  ///
  /// Returns null when absent and throws when multiple checkouts match, even if
  /// they happen to be at the same commit.
  Directory? find(Map<String, List<Directory>> index, String identity) {
    final matches = index[identity] ?? [];
    if (matches.length > 1) {
      throw StateError(
          'Multiple checkouts match a dependency: ${matches.map((repo) => repo.path).join(', ')}. Narrow workspace.search_roots or move the extra clone.');
    }
    return matches.isEmpty ? null : matches.single;
  }

  /// Rejects a checkout that is the consumer directory or one of its ancestors.
  void protectConsumer(Directory repository, Directory consumer) {
    if (p.equals(repository.path, consumer.path) ||
        p.isWithin(repository.path, consumer.path)) {
      throw StateError(
          'Refusing to synchronize the repository containing the consumer: ${repository.path}');
    }
  }

  /// Rejects any occupied clone destination, including files and symlinks.
  void protectNewTarget(Directory target) {
    if (FileSystemEntity.typeSync(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError(
          'Clone destination already exists: ${target.path}. Move it or clone the dependency under a unique name in a search root.');
    }
  }

  /// Rejects full replacement of worktrees, submodules, or nested repositories.
  ///
  /// Dirty files and unpublished commits are checked separately through Git.
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
