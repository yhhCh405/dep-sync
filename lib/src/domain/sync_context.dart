import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../infrastructure/git_url_normalizer.dart';
import '../infrastructure/manifest_repository.dart';
import '../infrastructure/pubspec_repository.dart';
import '../infrastructure/workspace_locator.dart';
import 'git_dependency.dart';
import 'ports/git_operations.dart';
import 'ports/pubspec_store.dart';
import 'workspace_manifest.dart';

/// Groups declarations that resolve to the same normalized Git repository.
///
/// [SyncContext.load] collects direct dependencies in [packages] so a repository
/// containing several Dart packages is synchronized once. [identity] is used for
/// matching; [url] retains a cloneable address rather than the normalized key.
class RepositoryDependency {
  /// Starts an empty group for a repository identity and its clone URL.
  RepositoryDependency(this.identity, this.url);
  final String identity;
  final String url;
  final packages = <GitDependency>[];
}

/// Validated input snapshot shared by pull and push orchestration.
///
/// Create through [load] from a consumer directory. It discovers the workspace,
/// loads configuration, applies exclusions, and groups declarations by repository.
/// [original] preserves the source text needed to detect concurrent pubspec edits.
/// Loading a context does not fetch, clone, check out, or write files.
class SyncContext {
  /// Stores already validated configuration, source text, and managed repositories.
  SyncContext._(this.consumer, this.workspace, this.manifest, this.pubspec,
      this.original, this.repositories);
  final Directory consumer;
  final Directory workspace;
  final WorkspaceManifest manifest;
  final File pubspec;
  final String original;
  final List<RepositoryDependency> repositories;

  /// Loads inputs from [cwd], or the current directory when omitted.
  ///
  /// Set [validateRefs] for pull to reject conflicting refs in one repository.
  /// Push disables that check because it will pin them to the same local HEAD.
  /// [pubspecs] supplies declaration parsing; ignored declarations remain visible
  /// until shared-repository conflicts have been checked. Invalid input throws.
  static SyncContext load(String? cwd,
      {required bool validateRefs,
      PubspecStore pubspecs = const PubspecRepository()}) {
    final consumer = Directory(
        Directory(cwd ?? Directory.current.path).resolveSymbolicLinksSync());
    final pubspec = File(p.join(consumer.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw StateError('pubspec.yaml not found in ${consumer.path}.');
    }
    if (FileSystemEntity.typeSync(pubspec.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('The consumer pubspec.yaml must not be a symlink.');
    }
    final workspace = const WorkspaceLocator().findWorkspaceRoot(consumer);
    final manifest = const ManifestRepository().load(workspaceRoot: workspace);
    final original = pubspec.readAsStringSync();
    final dependencies =
        pubspecs.readGitDependencies(pubspec, ignored: manifest.ignorePackages);
    const normalizer = GitUrlNormalizer();
    final ignoredUrls = dependencies
        .where((dep) => manifest.ignorePackages.contains(dep.name))
        .map((dep) => normalizer.normalize(dep.url, relativeTo: consumer.path))
        .toSet();
    final groups = <String, RepositoryDependency>{};
    for (final dependency in dependencies) {
      if (manifest.ignorePackages.contains(dependency.name)) continue;
      final identity =
          normalizer.normalize(dependency.url, relativeTo: consumer.path);
      if (ignoredUrls.contains(identity)) {
        throw StateError(
            '${dependency.name} shares a Git repository with an ignored package. Ignore every package from that repository or remove the exclusion.');
      }
      final group = groups.putIfAbsent(
          identity,
          () => RepositoryDependency(
              identity, normalizer.cloneUrl(dependency.url, consumer.path)));
      if (validateRefs &&
          group.packages.any((other) => other.ref != dependency.ref)) {
        throw StateError('Conflicting refs for packages in one repository: ${[
          ...group.packages.map((dep) => dep.name),
          dependency.name
        ].join(', ')}. Use the same ref or ignore the repository.');
      }
      group.packages.add(dependency);
    }
    return SyncContext._(consumer, workspace, manifest, pubspec, original,
        groups.values.toList());
  }
}

/// Checks each package name and path against the Git tree at [hash].
///
/// Use before moving a checkout or pinning refs. Reads committed pubspec content
/// through [git], rather than working files, and throws for missing or mismatched
/// packages without changing the repository.
Future<void> validatePackages(GitOperations git, Directory repository,
    String hash, RepositoryDependency group) async {
  for (final dependency in group.packages) {
    final path = dependency.path.isEmpty || dependency.path == '.'
        ? 'pubspec.yaml'
        : '${p.posix.normalize(dependency.path)}/pubspec.yaml';
    final content = await git.readFileAtCommit(repository, hash, path);
    if (content == null) {
      throw StateError(
          'Missing $path for ${dependency.name} at the requested commit.');
    }
    final yaml = loadYaml(content);
    if (yaml is! YamlMap || yaml['name'] != dependency.name) {
      throw StateError(
          'Package name at $path does not match ${dependency.name}. Check git.path and the selected ref.');
    }
  }
}
