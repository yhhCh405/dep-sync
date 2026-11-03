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
  test('allows version pins without treating them as path entries', () {
    expect(
        melosManagedPathOverrides(
            '# melos_managed_dependency_overrides: intl,bridge\n'
            'dependency_overrides:\n  intl: 0.19.0\n  bridge: {path: ../bridge}\n'),
        {'bridge': '../bridge'});
    expect(
        melosManagedPathOverrides(
            '${marker}dependency_overrides:\n  bridge: any\n'),
        isEmpty);
  });
  for (final content in [
    'dependency_overrides:\n  bridge: {path: ../bridge}\n',
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
