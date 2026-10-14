import 'package:dep_sync/src/infrastructure/pubspec_repository.dart';
import 'package:test/test.dart';
import 'support/fixture.dart';

void main() {
  late Fixture fixture;
  setUp(() => fixture = Fixture());
  tearDown(() => fixture.dispose());
  const repository = PubspecRepository();
  test('batch refs preserve comments, SDK, URLs, paths and other metadata', () {
    fixture.pubspec('''dependencies:
  one:
    git:
      url: https://example.com/one.git # URL comment
      ref: old # ref comment
      path: packages/one
      # preserve me
  two:
    git: https://example.com/two.git
''');
    final before = fixture.pubspecFile.readAsStringSync();
    final dependencies = repository.readGitDependencies(fixture.pubspecFile);
    repository.updateGitRefs(
        fixture.pubspecFile, {for (final dep in dependencies) dep: 'new'},
        original: before);
    final after = fixture.pubspecFile.readAsStringSync();
    expect(after, contains("sdk: '>=2.18.0 <3.0.0'"));
    expect(after, contains('# URL comment'));
    expect(after, contains('# preserve me'));
    expect(fixture.yaml['dependencies']['one']['git']['path'], 'packages/one');
    expect(fixture.yaml['dependencies']['two']['git']['url'],
        'https://example.com/two.git');
    expect(fixture.yaml['dependencies']['two']['git']['ref'], 'new');
  });
  test('concurrent edit aborts without overwriting user changes', () {
    fixture.pubspec('dependencies: {one: {git: https://example.com/one.git}}');
    final before = fixture.pubspecFile.readAsStringSync();
    final dep = repository.readGitDependencies(fixture.pubspecFile).single;
    fixture.pubspecFile.writeAsStringSync('$before# user edit\n');
    expect(
        () => repository.updateGitRefs(fixture.pubspecFile, {dep: 'new'},
            original: before),
        throwsStateError);
    expect(fixture.pubspecFile.readAsStringSync(), '$before# user edit\n');
  });
  test('rejects git.path escaping a checkout', () {
    fixture.pubspec(
        'dependencies: {one: {git: {url: https://example.com/one.git, path: ../outside}}}');
    expect(() => repository.readGitDependencies(fixture.pubspecFile),
        throwsFormatException);
  });
}
