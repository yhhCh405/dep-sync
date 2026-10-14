import 'dart:io';
import '../git_dependency.dart';

/// Reads Git dependency declarations and persists a complete set of ref edits.
///
/// Inject this into the pull/push use cases to replace pubspec persistence.
/// Implementations own YAML parsing and preservation; use cases decide which
/// dependencies are managed and resolve their commits before requesting a save.
abstract interface class PubspecStore {
  /// Reads direct Git declarations in dependencies, dev_dependencies, and
  /// dependency_overrides; throws for malformed managed declarations.
  ///
  /// [ignored] allows unsupported `tag_pattern` entries to be inspected for
  /// shared-repository conflicts. It does not filter dependencies from the
  /// result: the caller must apply exclusions before synchronizing repositories.
  List<GitDependency> readGitDependencies(File file,
      {Set<String> ignored = const {}});

  /// Saves all [refs] together, preserving unrelated YAML and dependency fields.
  ///
  /// [original] must be the exact source snapshot used to plan the updates.
  /// Implementations must reject a changed file before writing, construct the
  /// full edit before replacement, and leave the original intact on preparation
  /// failure. An empty update still checks for concurrent edits.
  void updateGitRefs(File file, Map<GitDependency, String> refs,
      {required String original});
}
