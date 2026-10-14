/// One Git dependency declaration from a consumer's pubspec.
///
/// Create these through `PubspecRepository.readGitDependencies`. Keep [section]
/// and [name] together to identify the YAML location when pinning a new ref;
/// [path] identifies a package inside the repository, not its clone destination.
class GitDependency {
  /// Captures a declaration without resolving its URL or checking out its ref.
  const GitDependency({
    required this.section,
    required this.name,
    required this.url,
    required this.ref,
    required this.path,
  });

  /// The declaring YAML section, such as `dependencies` or `dependency_overrides`.
  final String section;
  final String name;
  final String url;

  /// The declared Git revision; an empty value means remote HEAD during pull.
  final String ref;

  /// Repository-relative package path; an empty value means the repository root.
  final String path;

  /// Whether this declaration contains a Git URL.
  bool get hasGitUrl => url.isNotEmpty;

  /// Whether an explicit branch, tag, or commit was declared.
  bool get hasRef => ref.isNotEmpty;
}
