import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'git_dependency.dart';
import 'workspace_manifest.dart';
import '../infrastructure/git_url_normalizer.dart';
import '../infrastructure/manifest_repository.dart';
import '../infrastructure/pubspec_repository.dart';
import '../infrastructure/workspace_locator.dart';
import '../infrastructure/git_client.dart';

class RepositoryDependency {
  RepositoryDependency(this.identity, this.url);
  final String identity;
  final String url;
  final packages = <GitDependency>[];
}

class SyncContext {
  SyncContext._(this.consumer, this.workspace, this.manifest, this.pubspec,
      this.original, this.repositories);
  final Directory consumer;
  final Directory workspace;
  final WorkspaceManifest manifest;
  final File pubspec;
  final String original;
  final List<RepositoryDependency> repositories;

  static SyncContext load(String? cwd, {required bool validateRefs}) {
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
    final dependencies = const PubspecRepository()
        .readGitDependencies(pubspec, ignored: manifest.ignorePackages);
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

Future<void> validatePackages(GitClient git, Directory repository, String hash,
    RepositoryDependency group) async {
  for (final dependency in group.packages) {
    final path = dependency.path.isEmpty || dependency.path == '.'
        ? 'pubspec.yaml'
        : '${p.posix.normalize(dependency.path)}/pubspec.yaml';
    final content = await git.run(repository, ['show', '$hash:$path']);
    if (!content.succeeded) {
      throw StateError(
          'Missing $path for ${dependency.name} at the requested commit.');
    }
    final yaml = loadYaml(content.stdout);
    if (yaml is! YamlMap || yaml['name'] != dependency.name) {
      throw StateError(
          'Package name at $path does not match ${dependency.name}. Check git.path and the selected ref.');
    }
  }
}
