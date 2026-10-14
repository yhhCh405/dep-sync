import 'package:dep_sync/src/infrastructure/manifest_repository.dart';
import 'package:test/test.dart';

void main() {
  const repository = ManifestRepository();
  test('defaults and exclusions do not need a project list', () {
    final defaults = repository.parse('workspace: {}');
    expect(defaults.searchRoots, ['apps', 'packages']);
    expect(defaults.defaultCloneRoot, 'packages');
    final configured = repository.parse('''workspace:
  search_roots: [apps, libs]
  default_clone_root: libs
ignore_packages: [shared_widgets]
''');
    expect(configured.searchRoots, ['apps', 'libs']);
    expect(configured.defaultCloneRoot, 'libs');
    expect(configured.ignorePackages, {'shared_widgets'});
  });
  for (final invalid in [
    '',
    '[]',
    'projects: []',
    'project: []',
    'ignore_package: [foo]',
    'workspace: text',
    'workspace: {search_roots: apps}',
    'ignore_packages: [12]',
    'ignore_packages: ["foo*"]',
    'workspace: {default_clone_root: ../outside}',
    'workspace: {search_roots: [/tmp]}',
    'workspace: {default_clone_root: "C:/outside"}',
  ]) {
    test('rejects invalid manifest: $invalid', () {
      expect(() => repository.parse(invalid), throwsFormatException);
    });
  }
}
