import 'package:dep_sync/src/infrastructure/melos_overrides.dart';
import 'package:test/test.dart';

void main() {
  const marker = '# melos_managed_dependency_overrides: bridge\n';
  test('recognizes the legacy Melos marker and only pure managed paths', () {
    expect(
        melosManagedPathOverrides(
            '${marker}dependency_overrides:\n  bridge: {path: ../bridge}\n'),
        {'bridge': '../bridge'});
  });
  for (final content in [
    'dependency_overrides:\n  bridge: {path: ../bridge}\n',
    '${marker}dependency_overrides:\n  bridge: any\n',
    '${marker}dependency_overrides:\n  bridge: {path: ../bridge, version: any}\n',
    '${marker}dependency_overrides:\n  bridge: {path: ../bridge}\n  custom: any\n',
    '${marker}dependency_overrides:\n  bridge: {path: ../bridge} # keep this\n',
    '$marker# personal note\ndependency_overrides:\n  bridge: {path: ../bridge}\n',
    '${marker}resolution: other\ndependency_overrides:\n  bridge: {path: ../bridge}\n',
  ]) {
    test('does not claim ownership of modified or user configuration: $content',
        () {
      expect(melosManagedPathOverrides(content), isNull);
    });
  }
}
