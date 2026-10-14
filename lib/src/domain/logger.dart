class Logger {
  const Logger({required this.verbose});

  final bool verbose;

  void info(String message) => print('[i] $message');
  void ok(String message) => print('[ok] $message');
  void warn(String message) => print('[!] $message');
  void debug(String message) {
    if (verbose) {
      print('[d] $message');
    }
  }

  Never fail(String message, {int exitCode = 1}) {
    throw DepSyncException(message, exitCode: exitCode);
  }
}

class DepSyncException implements Exception {
  const DepSyncException(this.message, {this.exitCode = 1});

  final String message;
  final int exitCode;

  @override
  String toString() => message;
}
