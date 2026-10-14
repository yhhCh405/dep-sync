import 'dart:io';

import 'package:path/path.dart' as p;

import '../infrastructure/git_client.dart';
import '../infrastructure/git_url_normalizer.dart';
import '../infrastructure/pubspec_repository.dart';
import '../infrastructure/repository_locator.dart';
import 'logger.dart';
import 'options.dart';
import 'ports/git_operations.dart';
import 'ports/pubspec_store.dart';
import 'sync_context.dart';

/// Synchronizes local dependency repositories to the consumer's declared refs.
///
/// Call `await DepPullUseCase().run(PullOptions(cwd: consumerPath))`. Inject
/// [GitOperations] or [PubspecStore] to replace external operations while keeping
/// validation and checkout planning. The use case applies package exclusions and
/// prepares all refs before moving existing checkouts; it does not edit pubspecs,
/// SDK settings, or workspace files.
class DepPullUseCase {
  /// Uses the Git command-line and YAML file adapters unless substitutes are supplied.
  DepPullUseCase({GitOperations? git, PubspecStore? pubspecs})
      : _git = git ?? GitClient(),
        _pubspecs = pubspecs ?? const PubspecRepository();
  final GitOperations _git;
  final PubspecStore _pubspecs;

  /// Validates, prepares, and applies the synchronization requested by [options].
  ///
  /// Fails before checkout changes for invalid refs, unsafe destinations, ignored
  /// repository conflicts, or unapproved local changes. Fetch metadata may change
  /// during preparation; application across multiple repositories is not atomic.
  /// Temporary clones are cleaned up unless needed to recover a failed replacement.
  Future<void> run(PullOptions options) async {
    final context =
        SyncContext.load(options.cwd, validateRefs: true, pubspecs: _pubspecs);
    final logger = Logger(verbose: options.verbose);
    logger.debug(
        'Workspace: ${context.workspace.path}; ignored packages: ${context.manifest.ignorePackages.join(', ')}');
    final fallback = options.fallbackBranch;
    if (fallback != null &&
        (fallback.isEmpty ||
            fallback.startsWith('-') ||
            RegExp(r'[\x00-\x1f]').hasMatch(fallback))) {
      throw FormatException('--fallback-branch requires a valid branch name.');
    }
    if (context.repositories.isEmpty) {
      logger.info('No managed Git dependencies.');
      return;
    }
    final locator = RepositoryLocator(_git);
    final index = await locator.index(context.workspace, context.manifest);
    final plans = <_PullPlan>[];
    // Validate every destination and working tree before fetching or cloning.
    for (final group in context.repositories) {
      final existing = locator.find(index, group.identity);
      final target = existing ??
          locator.safeDirectory(context.workspace,
              '${context.manifest.defaultCloneRoot}/${const GitUrlNormalizer().repoName(group.url)}');
      locator.protectConsumer(target, context.consumer);
      for (final plan in plans) {
        if (p.equals(target.path, plan.target.path) ||
            p.isWithin(target.path, plan.target.path) ||
            p.isWithin(plan.target.path, target.path)) {
          throw StateError(
              'Dependency checkout paths collide: ${target.path}. Clone the repositories under distinct names in a search root.');
        }
      }
      if (existing == null) {
        locator.protectNewTarget(target);
      } else {
        if (options.fresh) locator.protectFresh(existing);
        if (!options.force &&
            await _git.hasLocalChanges(existing,
                includeIgnored: options.fresh)) {
          throw StateError(
              'Local changes${options.fresh ? ' or ignored files' : ''} in ${existing.path}. Commit, stash, or use --force to discard them.');
        }
        if (options.fresh &&
            !options.force &&
            await _git.hasUnpushedCommits(existing)) {
          throw StateError(
              'Local commits are not on origin in ${existing.path}. Push them before --fresh, or explicitly discard with --force.');
        }
      }
      plans.add(_PullPlan(group, target, existing != null));
    }
    try {
      // Resolve all refs and package paths before any existing checkout moves.
      for (final plan in plans) {
        if (!plan.existed || options.fresh) {
          plan.target.parent.createSync(recursive: true);
          plan.staging = plan.target.parent.createTempSync('.dep-sync-clone-');
          plan.prepared = Directory(p.join(plan.staging!.path, 'repo'));
          await _git.clone(plan.group.url, plan.prepared!);
        } else {
          plan.prepared = plan.target;
        }
        plan.hash = await _resolve(
            plan.prepared!, plan.group.packages.first.ref, options, logger);
        await validatePackages(_git, plan.prepared!, plan.hash!, plan.group);
        if (plan.existed && !options.force && !options.fresh) {
          await _git.protectDetachedHead(plan.target, plan.hash!);
        }
        if (plan.staging != null) {
          await _git.checkout(plan.prepared!, plan.hash!, force: false);
        }
      }
      for (final plan in plans) {
        if (plan.staging == null) {
          // Recheck after network operations in case the working tree changed.
          if (!options.force && await _git.hasLocalChanges(plan.target)) {
            throw StateError(
                'Local changes appeared during synchronization in ${plan.target.path}.');
          }
          await _git.checkout(plan.target, plan.hash!, force: options.force);
        } else if (plan.existed) {
          if (!options.force &&
              (await _git.hasLocalChanges(plan.target, includeIgnored: true) ||
                  await _git.hasUnpushedCommits(plan.target))) {
            throw StateError(
                'Local changes appeared before replacing ${plan.target.path}.');
          }
          final backupPath = p.join(plan.staging!.path, 'previous');
          plan.target.renameSync(backupPath);
          try {
            plan.prepared!.renameSync(plan.target.path);
          } catch (_) {
            try {
              Directory(backupPath).renameSync(plan.target.path);
            } catch (_) {
              plan.preserveStaging = true;
              throw StateError(
                  'Could not restore the previous clone. It is preserved at $backupPath.');
            }
            rethrow;
          }
        } else {
          locator.protectNewTarget(plan.target);
          plan.prepared!.renameSync(plan.target.path);
        }
        logger.ok(
            '${plan.group.packages.map((dep) => dep.name).toSet().join(', ')} at ${plan.hash} (${p.relative(plan.target.path, from: context.workspace.path)})');
      }
    } finally {
      for (final plan in plans) {
        final staging = plan.staging;
        if (!plan.preserveStaging && staging != null && staging.existsSync()) {
          staging.deleteSync(recursive: true);
        }
      }
    }
    logger.ok('Synchronized ${plans.length} repository(s).');
  }

  /// Resolves a declaration, fetching when necessary and applying branch options.
  ///
  /// Returns a commit hash or throws when neither the requested ref nor the
  /// optional fallback resolves. It changes fetch metadata, never working files.
  Future<String> _resolve(Directory repository, String ref, PullOptions options,
      Logger logger) async {
    var fetched = false;
    if (options.repoUpdate || options.pullBranchLatest || ref.isEmpty) {
      await _git.fetch(repository);
      fetched = true;
    }
    var hash = await _git.resolveDeclared(repository, ref);
    if (hash == null && !fetched) {
      await _git.fetch(repository);
      fetched = true;
      hash = await _git.resolveDeclared(repository, ref);
    }
    if (hash == null && options.fallbackBranch != null) {
      if (!fetched) await _git.fetch(repository);
      hash = await _git.resolve(
          repository, 'refs/remotes/origin/${options.fallbackBranch}');
      if (hash != null) {
        logger.warn(
            'Requested ref missing; using fallback branch ${options.fallbackBranch}.');
      }
    }
    if (hash == null) {
      throw StateError(
          'Cannot resolve Git ref "${ref.isEmpty ? 'remote HEAD' : ref}" in ${repository.path}.');
    }
    final branchTip = ref.isEmpty
        ? null
        : await _git.resolve(repository, 'refs/remotes/origin/$ref');
    if (options.pullBranchLatest) {
      hash = branchTip ?? await _git.containingBranchTip(repository, hash);
    } else if (options.repoUpdate && branchTip != null) {
      hash = branchTip;
    }
    return hash;
  }
}

/// Mutable preparation state for one repository in a pull operation.
///
/// Created after destination checks, then populated with a prepared checkout
/// and resolved hash before application. [staging] owns temporary clones and
/// replacement backups; [preserveStaging] keeps recovery data on restore failure.
class _PullPlan {
  /// Records the dependency group, final checkout location, and preexisting state.
  _PullPlan(this.group, this.target, this.existed);
  final RepositoryDependency group;
  final Directory target;
  final bool existed;
  Directory? staging;
  Directory? prepared;
  String? hash;
  bool preserveStaging = false;
}
