import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../domain/logger.dart';
import 'process_runner.dart';

/// Resolves a prepared native Pub workspace without Melos-generated overrides.
class WorkspacePubResolver {
  /// Accepts an alternate process executor for offline tests.
  const WorkspacePubResolver({this.runner = const ProcessRunner()});

  final ProcessExecutor runner;

  /// Honors the consumer FVM pin, falling back to the workspace pin or PATH.
  /// A failed resolution leaves synchronized repositories available for retry.
  Future<void> resolve(
      Directory workspace, Directory consumer, Logger logger) async {
    Directory? pinned;
    String? version;
    for (final directory in [consumer, workspace]) {
      final config = File(p.join(directory.path, '.fvmrc'));
      final legacy = File(p.join(directory.path, '.fvm', 'fvm_config.json'));
      if (!config.existsSync() && !legacy.existsSync()) continue;
      final data = jsonDecode(
          (config.existsSync() ? config : legacy).readAsStringSync());
      final value = data is Map
          ? data[config.existsSync() ? 'flutter' : 'flutterSdkVersion']
          : null;
      if (value is! String ||
          value.isEmpty ||
          value.startsWith('-') ||
          RegExp(r'[\x00-\x20]').hasMatch(value)) {
        throw FormatException('Invalid Flutter SDK pin in ${directory.path}.');
      }
      pinned = directory;
      version = value;
      break;
    }
    final log = File(p.join(workspace.path, '.dep-sync', 'pub-get.log'));
    log.parent.createSync(recursive: true);
    log.writeAsStringSync('');
    final started = DateTime.now();
    final progress = Timer.periodic(const Duration(seconds: 10), (_) {
      logger.info(
          'Pub resolution is still running (${DateTime.now().difference(started).inSeconds}s elapsed)...');
    });
    Future<void> run(
        String executable, List<String> arguments, Directory cwd) async {
      logger.info('Running $executable ${arguments.join(' ')}');
      CommandResult result;
      try {
        result =
            await runner.run(executable, arguments, workingDirectory: cwd.path);
      } on ProcessException catch (error) {
        throw StateError('Could not run $executable: ${error.message}. '
            '${pinned != null ? 'Install FVM and the pinned Flutter SDK $version.' : 'Install the required SDK on PATH.'} '
            'Retry dep-pull or use --skip-pub-get for checkout only.');
      }
      log.writeAsStringSync('${result.stdout}\n${result.stderr}\n',
          mode: FileMode.append);
      if (result.stdout.isNotEmpty) stdout.write(result.stdout);
      if (result.stderr.isNotEmpty) stderr.write(result.stderr);
      if (!result.succeeded) {
        throw StateError(
            'Pub resolution command failed (exit ${result.exitCode}). '
            'Repositories are synchronized. Full log: ${log.path}');
      }
    }

    try {
      logger.info('Pub resolution log: ${log.path}');
      if (pinned != null) {
        logger.info('Using pinned Flutter SDK $version from ${pinned.path}.');
        // FVM runs in the pin owner; Pub discovers and resolves its enclosing workspace.
        await run('fvm', ['install', version!], pinned);
        await run('fvm', ['flutter', 'pub', 'get', '--no-example'], pinned);
      } else {
        var flutter = false;
        final visited = <String>{};
        void inspect(Directory directory) {
          if (!visited.add(p.normalize(directory.absolute.path))) return;
          final source = loadYaml(File(p.join(directory.path, 'pubspec.yaml'))
              .readAsStringSync()) as Map;
          final overrideFile =
              File(p.join(directory.path, 'pubspec_overrides.yaml'));
          final overrides = overrideFile.existsSync()
              ? loadYaml(overrideFile.readAsStringSync()) as Map
              : const {};
          // Pub overrides replace whole fields, including workspace membership
          // and dependency sections; do not traverse overridden-away packages.
          final yaml = {...source, ...overrides};
          if (yaml['environment'] is Map &&
              (yaml['environment'] as Map).containsKey('flutter')) {
            flutter = true;
          }
          for (final section in ['dependencies', 'dev_dependencies']) {
            final entries = yaml[section];
            if (entries is Map &&
                entries.values.any(
                    (value) => value is Map && value['sdk'] == 'flutter')) {
              flutter = true;
            }
          }
          for (final child in yaml['workspace'] as List? ?? []) {
            inspect(Directory(p.join(directory.path, child as String)));
          }
        }

        inspect(workspace);
        // inspect follows the validated explicit workspace membership, including nested members.
        await run(
            flutter
                ? (Platform.isWindows ? 'flutter.bat' : 'flutter')
                : Platform.resolvedExecutable,
            ['pub', 'get', if (flutter) '--no-example'],
            workspace);
      }
      logger.ok('Pub workspace dependencies resolved.');
    } finally {
      progress.cancel();
    }
  }
}
