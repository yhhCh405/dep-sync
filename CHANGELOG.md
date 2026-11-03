# Changelog

## 0.2.2

- Migrate redundant, untracked Melos-generated path override files when enabling
  Pub workspaces; preserve user/tracked overrides and report member conflicts
  before checkout instead of generating a workspace Pub cannot resolve.
- Keep override-only packages outside automatically generated workspace membership.
- Refresh a shell-compatible `dep-sync.lock` receipt after every successful push,
  including already-pinned and no-dependency runs. Preserve previous receipts
  when validation or pubspec persistence fails.
- Share the tool version between CLI output and receipts.

## 0.2.1

- Refresh the README with clearer onboarding, workspace examples, configuration
  guidance, and navigation.
- Correct example commit hashes and document SchemaStore registration progress.
- Remove the redundant parent example manifest; each sample workspace retains
  its own configuration.
- Skip existing release tags safely and document publication retries.

## 0.2.0

- Print the DEP-SYNC product notice from the dep-pull and dep-push aliases.
- Keep the publishable Dart 3 CLI constraint; generated unpublished workspace
  roots require Dart 3.6 or later without an explicit upper bound.

- Add opt-in `workspace.use_resolution_workspace` to prepare Pub workspace roots
  and resolution overrides after a successful pull, without rewriting SDK constraints.
- Include managed package paths, recursive local dependencies, and explicit nested
  workspace members; preserve existing user configuration and detect conflicts.
- Track generated files for safe updates and stale override cleanup.
- Add a manifest JSON Schema for VS Code YAML hover help, completion, and validation.
- Demonstrate Pub workspace resolution in example workspace 2.
- Add automatic version tagging after successful main CI and OIDC publication from
  validated tags; document required release-token and pub.dev configuration.

## 0.1.1
- Updated document and examples

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
