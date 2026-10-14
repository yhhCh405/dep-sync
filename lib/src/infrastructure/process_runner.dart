import 'dart:io';

import 'package:path/path.dart' as p;

/// Captured exit status and text output from a completed child process.
///
/// Returned by [ProcessExecutor.run]. Check [succeeded] before using [stdout] as
/// successful command data; a nonzero exit is represented here rather than thrown.
class CommandResult {
  /// Creates a completed result, also useful for substitute process executors.
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  /// Whether the child process exited with status zero.
  bool get succeeded => exitCode == 0;
}

/// Executes a process without requiring callers to use `dart:io` directly.
///
/// Supply an implementation to `GitClient` to substitute command execution,
/// for example to simulate an unavailable remote in an integration test.
abstract interface class ProcessExecutor {
  /// Runs [executable] with separate [arguments] and captures its output.
  ///
  /// [workingDirectory] selects the child process directory; [environment]
  /// overrides inherited environment values. A nonzero exit is returned as a
  /// [CommandResult], while failure to start the process throws.
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

/// Executes commands through Dart processes without shell interpolation.
///
/// Use [run] with executable and argument strings kept separate. Optional
/// [extraPathEntries] are prepended to the inherited PATH for command discovery.
/// Implements [ProcessExecutor], allowing callers to inject an alternative runner.
class ProcessRunner implements ProcessExecutor {
  /// Creates a runner with optional directories prepended to the process PATH.
  const ProcessRunner({this.extraPathEntries = const []});

  final List<String> extraPathEntries;

  /// Starts a child process and returns its completed status and text output.
  ///
  /// Inherits the parent environment with supplied overrides. When configured,
  /// [extraPathEntries] rebuilds PATH from those entries and the parent PATH.
  /// Process startup failures propagate; a nonzero child exit is returned normally.
  @override
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

  /// Looks up an executable using the platform's `which` or `where` command.
  ///
  /// Returns the first output line, null on lookup failure, or an empty string if
  /// a successful lookup produced no nonempty lines.
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

/// Joins nonempty entries using the platform PATH-list separator, not a file separator.
String joinPath(Iterable<String> entries) {
  final separator = Platform.isWindows ? ';' : ':';
  return entries.where((entry) => entry.isNotEmpty).join(separator);
}

/// Returns [child] relative to [parent], using forward slashes for configuration text.
String relativePath(String child, String parent) =>
    p.relative(child, from: parent).replaceAll(r'\', '/');
