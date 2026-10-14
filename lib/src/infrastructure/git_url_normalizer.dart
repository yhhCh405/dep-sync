import 'dart:io';
import 'package:path/path.dart' as p;

/// Separates repository identity matching from Git's clone address syntax.
///
/// Use [normalize] to compare HTTPS, SSH, SCP-style, and local origins. Use
/// [cloneUrl] for the address passed to Git and [repoName] for a destination name;
/// normalized identity keys are not necessarily cloneable URLs.
class GitUrlNormalizer {
  /// Creates a stateless Git address helper.
  const GitUrlNormalizer();

  /// Returns an identity key, resolving local paths against [relativeTo].
  ///
  /// Network identities omit transport and credentials while retaining host, port,
  /// and repository path. Existing local directories are resolved through symlinks;
  /// local paths default to the current directory when [relativeTo] is omitted.
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

  /// Makes local relative URLs absolute from [consumerPath], preserving remote URLs.
  String cloneUrl(String input, String consumerPath) {
    if (input.contains('://') ||
        (RegExp(r'^[^/]+:').hasMatch(input) && !p.windows.isAbsolute(input))) {
      return input;
    }
    return p.normalize(p.absolute(p.join(consumerPath, input)));
  }

  /// Derives a checkout basename without `.git`; rejects unusable directory names.
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

  /// Removes trailing slashes and the optional `.git` suffix from remote identities.
  String _stripSuffix(String value) => value
      .replaceFirst(RegExp(r'/+$'), '')
      .replaceFirst(RegExp(r'\.git$'), '');
}
