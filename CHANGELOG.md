# Changelog

## 0.1.0

- Introduce `dep-sync pull` and `dep-sync push`, plus `dep-pull` and `dep-push`
  executable aliases.
- Read direct Git dependencies from consumer pubspecs and route clones through
  `.dep-sync/manifest.yaml` workspace settings without a repository list.
- Support `ignore_packages` by exact dependency name, including shared-repository
  conflict detection.
- Synchronize and pin refs using Git alone, without Flutter/FVM version detection,
  SDK constraint edits, Pub Workspace generation, or Melos dependencies.
- Validate every ref and package path before applying checkouts; protect dirty
  clones, ambiguous origins, consumer repositories, and unsafe destinations.
- Stage replacement clones before `--fresh`; protect ignored files and unpublished
  commits unless explicitly discarded with `--force`.
- Pin all refs in one atomic pubspec replacement, fail on missing/dirty checkouts,
  and preserve other YAML content.
- Include a local demonstration, integration tests, and multi-platform CI.
