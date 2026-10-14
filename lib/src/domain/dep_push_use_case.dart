import '../infrastructure/git_client.dart';
import '../infrastructure/pubspec_repository.dart';
import '../infrastructure/repository_locator.dart';
import 'git_dependency.dart';
import 'logger.dart';
import 'options.dart';
import 'sync_context.dart';

class DepPushUseCase {
  DepPushUseCase({GitClient? git}) : _git = git ?? GitClient();
  final GitClient _git;

  Future<void> run(PushOptions options) async {
    final context = SyncContext.load(options.cwd, validateRefs: false);
    final logger = Logger(verbose: options.verbose);
    logger.debug(
        'Workspace: ${context.workspace.path}; ignored packages: ${context.manifest.ignorePackages.join(', ')}');
    if (context.repositories.isEmpty) {
      logger.info('No managed Git dependencies.');
      return;
    }
    final locator = RepositoryLocator(_git);
    final index = await locator.index(context.workspace, context.manifest);
    final updates = <GitDependency, String>{};
    for (final group in context.repositories) {
      final repository = locator.find(index, group.identity);
      if (repository == null) {
        throw StateError(
            'Local checkout missing for ${group.packages.first.name}. Run dep-sync pull first. No refs were written.');
      }
      locator.protectConsumer(repository, context.consumer);
      if (await _git.hasLocalChanges(repository)) {
        throw StateError(
            'Uncommitted changes in ${repository.path}. Commit or stash before pinning refs. No refs were written.');
      }
      final hash = await _git.head(repository);
      await validatePackages(_git, repository, hash, group);
      for (final dependency in group.packages) {
        if (dependency.ref != hash) updates[dependency] = hash;
      }
    }
    const PubspecRepository()
        .updateGitRefs(context.pubspec, updates, original: context.original);
    logger.ok(
        'Pinned ${updates.length} Git ref(s). This does not push commits; publish dependency commits with Git before sharing the consumer pubspec.');
  }
}
