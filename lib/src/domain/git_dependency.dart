class GitDependency {
  const GitDependency({
    required this.section,
    required this.name,
    required this.url,
    required this.ref,
    required this.path,
  });

  final String section;
  final String name;
  final String url;
  final String ref;
  final String path;

  bool get hasGitUrl => url.isNotEmpty;
  bool get hasRef => ref.isNotEmpty;
}
