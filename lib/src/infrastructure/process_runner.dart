import 'dart:io';

import 'package:path/path.dart' as p;

class CommandResult {
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;
}

class ProcessRunner {
  const ProcessRunner({this.extraPathEntries = const []});

  final List<String> extraPathEntries;

  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final mergedEnvironment = <String, String>{
      ...Platform.environment,
      if (environment != null) ...environment,
    };

    if (extraPathEntries.isNotEmpty) {
      final separator = Platform.isWindows ? ';' : ':';
      mergedEnvironment['PATH'] = [
        ...extraPathEntries,
        Platform.environment['PATH'] ?? '',
      ].join(separator);
    }

    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: mergedEnvironment,
    );

    return CommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  Future<String?> which(String executable) async {
    final command = Platform.isWindows ? 'where' : 'which';
    final result = await run(command, [executable]);
    if (!result.succeeded) {
      return null;
    }
    return result.stdout.split('\n').map((line) => line.trim()).firstWhere(
          (line) => line.isNotEmpty,
          orElse: () => '',
        );
  }
}

String joinPath(Iterable<String> entries) {
  final separator = Platform.isWindows ? ';' : ':';
  return entries.where((entry) => entry.isNotEmpty).join(separator);
}

String relativePath(String child, String parent) =>
    p.relative(child, from: parent).replaceAll(r'\', '/');
