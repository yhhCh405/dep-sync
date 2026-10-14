import 'dart:io';
import 'package:path/path.dart' as p;

class GitUrlNormalizer {
  const GitUrlNormalizer();

  String normalize(String input, {String? relativeTo}) {
    var value = input.trim();
    final uri = Uri.tryParse(value);
    if (value.startsWith('file://')) {
      value = uri!.toFilePath();
    } else if (value.contains('://') && uri != null) {
      final port = uri.hasPort ? ':${uri.port}' : '';
      value = '${uri.host.toLowerCase()}$port${uri.path}';
      return _stripSuffix(value);
    } else {
      final scp = RegExp(r'^(?:[^/@:]+@)?([^/:]+):(.+)$').firstMatch(value);
      if (scp != null && !p.windows.isAbsolute(value)) {
        return _stripSuffix('${scp.group(1)!.toLowerCase()}/${scp.group(2)}');
      }
    }
    value = p.normalize(
        p.absolute(p.join(relativeTo ?? Directory.current.path, value)));
    final directory = Directory(value);
    return directory.existsSync()
        ? directory.resolveSymbolicLinksSync()
        : value;
  }

  String cloneUrl(String input, String consumerPath) {
    if (input.contains('://') ||
        (RegExp(r'^[^/]+:').hasMatch(input) && !p.windows.isAbsolute(input))) {
      return input;
    }
    return p.normalize(p.absolute(p.join(consumerPath, input)));
  }

  String repoName(String input) {
    final normalized = normalize(input);
    final name = p.posix
        .basename(normalized.replaceAll('\\', '/'))
        .replaceFirst(RegExp(r'\.git$'), '');
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(name)) {
      throw FormatException(
          'Cannot derive a safe checkout directory from the Git URL.');
    }
    return name;
  }

  String _stripSuffix(String value) => value
      .replaceFirst(RegExp(r'/+$'), '')
      .replaceFirst(RegExp(r'\.git$'), '');
}
