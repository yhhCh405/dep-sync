/// Writes consistently prefixed CLI progress messages to standard output.
///
/// Create one per operation using its verbosity option, then use [info], [ok],
/// or [warn] for normal progress and [debug] for optional diagnostic details.
/// [fail] throws an exception; it does not terminate the process itself.
class Logger {
  /// Creates a logger that emits diagnostic messages only when [verbose] is true.
  const Logger({required this.verbose});

  final bool verbose;

  /// Writes a normal progress message.
  void info(String message) => print('[i] $message');

  /// Writes a successful operation message.
  void ok(String message) => print('[ok] $message');

  /// Writes a warning without interrupting the current operation.
  void warn(String message) => print('[!] $message');

  /// Writes a diagnostic message when verbose output is enabled.
  void debug(String message) {
    if (verbose) {
      print('[d] $message');
    }
  }

  /// Throws [DepSyncException] with the supplied message and suggested exit code.
  Never fail(String message, {int exitCode = 1}) {
    throw DepSyncException(message, exitCode: exitCode);
  }
}

/// An operation failure carrying a message and a suggested process exit code.
///
/// Raised by [Logger.fail]. Callers must catch it and decide how to display the
/// message or apply [exitCode]; constructing or throwing it does not exit Dart.
class DepSyncException implements Exception {
  /// Creates a failure whose default suggested exit code is 1.
  const DepSyncException(this.message, {this.exitCode = 1});

  final String message;
  final int exitCode;

  /// Returns the user-facing failure message.
  @override
  String toString() => message;
}
