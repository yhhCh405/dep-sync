# dep_sync

Keep local Git dependency repositories in sync with your Dart or Flutter app.

## The problem

A multi-repository app might depend on a shared UI library, an authentication
package, and an API client, each maintained in its own Git repository. The app's
`pubspec.yaml` records which refs it needs, while developers keep separate local
clones to inspect, debug, and change those packages.

Those two views of the project can drift apart. Switching the app to a release
branch does not switch its sibling repositories. Committing a fix in a dependency
does not update the app's declared ref. Keeping everything aligned becomes a
manual task repeated across repositories and developers.

Pub already downloads Git dependencies for package resolution. The extra work
is maintaining the editable checkouts around the app and recording the commits
that should be shared with the team.

## The pain points

- **Setting up a workspace:** a new developer has to find each dependency URL,
  clone the repository, and check out the right ref.
- **Switching app branches or releases:** local dependency checkouts can remain
  on yesterday's code, so the code being inspected may differ from the version
  declared by the app.
- **Making changes across repositories:** after committing dependency changes,
  developers must copy the correct commit hashes into the app's pubspec without
  missing a package or editing the wrong declaration.
- **Handing work to a teammate:** instructions such as “pull these three repos
  and use these branches” leave room for different local states. Moving branches
  make that harder to reproduce over time.
- **Keeping exceptions under control:** some packages are managed separately
  and should be left alone during a synchronization run.

## The solution

dep-sync uses the consuming app's `pubspec.yaml` as the source of truth and
provides two directions of synchronization:

| Command | Direction | What it does |
| --- | --- | --- |
| `dep-sync pull` | App refs → local checkouts | Finds matching repositories by Git origin, clones missing ones, and checks out the declared refs. |
| `dep-sync push` | Local commits → app refs | Reads dependency HEAD commits and pins their hashes in the app's pubspec. |

For example, an app release may pin `shared_widgets` to one commit and
`auth_client` to another. Run `dep-sync pull` from that app to align both local
checkouts. After developing, committing, and pushing a dependency fix with Git,
run `dep-sync push` to record the new commit in the app. Commit that pubspec
change so a teammate can pull the same dependency commits.

**`dep-sync push` updates dependency refs; it does not upload commits.** Push the
dependency commits to their Git remotes before sharing the updated app pubspec.
Use commit hashes when you need reproducible checkouts; branch refs can move.

A small `.dep-sync/manifest.yaml` at the shared workspace root defines where
repositories are searched for and cloned. `ignore_packages` excludes dependencies
you manage separately. Adding or removing a dependency happens in the app's
pubspec—there is no second repository list to maintain.

The default workflow protects dirty checkouts, rejects ambiguous repository
matches, and validates all managed dependencies before writing pinned refs.
Destructive pull behavior requires explicit flags.

## How it fits your workflow

dep-sync manages **direct Git dependency checkouts and their declared refs**.
You keep your existing Git remotes, branches, SDK versions, and build workflow.
For live development against the local clones, configure path overrides or a
workspace yourself; cloning alone does not redirect Pub to those checkouts.

The tool runs through Git without selecting Flutter/FVM versions, changing SDK
constraints, generating workspace files, or running Melos. Your normal Pub or
Flutter commands remain responsible for package resolution and builds.

## Requirements and installation

- Dart 3.6 or later, below 4.0, to run the CLI.
- Git on `PATH` and access to your dependency repositories (SSH keys or your
  normal Git HTTPS credential helper).
- macOS, Linux, or Windows.

After the package is published to pub.dev:

```sh
dart pub global activate dep_sync
```

To install from this repository before publication:

```sh
git clone https://github.com/yhhCh405/dep-sync.git
cd dep-sync
dart pub global activate --source path .
```

Add your Pub cache's `bin` directory to `PATH` if Dart prints a warning. Its
default location is `$HOME/.pub-cache/bin` on macOS/Linux and
`%LOCALAPPDATA%\Pub\Cache\bin` on Windows. A custom `PUB_CACHE` changes this path.

The CLI's Dart requirement applies only to the CLI. It does not inspect, select,
install, or modify the consumer's Dart, Flutter, or FVM version. It does not run
Pub or Melos, generate workspaces, or edit SDK constraints or override files.

## Quick start

Create a shared parent folder and clone your app into it:

```text
my_project/
├── .dep-sync/
│   └── manifest.yaml
├── apps/
│   └── my_app/
│       └── pubspec.yaml
└── packages/
```

Create `my_project/.dep-sync/manifest.yaml`:

```yaml
workspace:
  search_roots:
    - apps
    - packages
  default_clone_root: packages

ignore_packages: []
```

In `apps/my_app/pubspec.yaml`, declare the Git dependencies you need:

```yaml
dependencies:
  shared_widgets:
    git:
      url: git@github.com:your-org/shared_widgets.git
      ref: main
      # For a package below the repository root, add:
      # path: packages/shared_widgets
```

Run from the consumer's directory:

```sh
cd my_project/apps/my_app
dep-sync pull
```

The tool finds the nearest ancestor containing `.dep-sync/manifest.yaml`,
finds existing checkouts by their Git origin, and clones missing ones into
`packages/<repository-name>`. It validates each package's `git.path` and name at
the selected commit, then checks out a **detached HEAD**. Existing local branches
are preserved. Use `git switch -c my-change` in a dependency before developing
new commits there.

**Cloning does not change how Dart resolves dependencies.** Git dependencies in
your pubspec still resolve through Pub's Git cache. For live local development,
use your own path overrides or an existing workspace setup. Run your usual
`dart pub get`, `flutter pub get`, or bootstrap workflow yourself. dep-sync leaves
that configuration under your control.

For a runnable demonstration that uses only local Git repositories, see
[the example](example/README.md).

## Everyday workflow

### Add a dependency

Add its Git declaration to the consumer's `pubspec.yaml`, then run
`dep-sync pull`. No manifest entry is needed. Regular hosted, SDK, and path
dependencies are left alone.

### Remove a dependency

Remove the declaration from the consumer's pubspec (including any corresponding
`dev_dependencies` or `dependency_overrides` declaration). Subsequent commands
stop managing it. The local clone is retained; delete it yourself only when you
no longer need its files or commits. Removing the last Git dependency is a no-op.

### Share dependency changes

1. Create a branch in the dependency checkout, make changes, and commit them.
2. Push the dependency commits using Git so teammates can fetch them.
3. From the consumer directory, run `dep-sync push`.
4. Review and commit the consumer's updated `pubspec.yaml` and refresh its lockfile
   with your normal Pub workflow when appropriate.
5. Teammates run `dep-sync pull` to synchronize to the pinned commits.

`push` reads clean local checkouts directly through Git. Every managed dependency
must resolve successfully before any ref is written. Updates are saved together
using a temporary file and rename; unrelated YAML, URLs, paths, comments, and SDK
constraints are preserved. Git shorthand (`git: <url>`) becomes a map containing
`url` and `ref`. The tool checks for concurrent pubspec edits before saving.

### Ignore a package

Use exact dependency names from the consumer's pubspec:

```yaml
workspace:
  search_roots: [apps, packages]
  default_clone_root: packages

ignore_packages:
  - experimental_sdk
  - shared_widgets
```

Ignored packages are not cloned, checked out, fetched, recloned, or pinned.
Existing declarations and files remain untouched, including with `--force` or
`--fresh`. This does not exclude them from Dart/Flutter dependency resolution.

If an ignored package shares a repository with a managed package, both commands
fail before modifying that repository. Ignore all packages from it or remove the
exclusion. Package names are not globs, folder names, or Git URLs.

## Commands

```sh
dep-sync --help
dep-sync --version
dep-sync pull [options]
dep-sync push [options]
```

`dep-pull` and `dep-push` are executable aliases. Both commands support
`--cwd <consumer-directory>` and `--verbose`. `DEP_SYNC_VERBOSE=1` also enables
verbose output.

Pull options:

| Option | Behavior |
| --- | --- |
| `--repo-update` | Fetch and select the remote tip when the declared ref names a branch. Does not merge into or reset your local branch. |
| `--pull-branch` | Fetch and use the tip of the unique remote branch containing a commit/tag. Ambiguous matches fail; use an explicit branch with `--repo-update`. |
| `--fallback-branch <name>` | Use that remote branch if the requested ref cannot be resolved. Logs a warning; does not rewrite the declared ref. |
| `--force` | Discard tracked changes and untracked files in managed checkouts. Ordinary pull still protects ignored files from checkout collisions. |
| `--fresh` | Prepare replacement clones and validate refs before replacing existing clones. Without `--force`, refuses local/ignored files and unpublished commits. |

`--fresh --force` also discards ignored files and unpublished commits in the
replaced clones. Use it only when those clones are disposable. `--fresh` refuses
Git worktrees, submodules, and repositories containing nested repositories.

By default, an existing local branch is resolved at its local tip. A remote branch
is used when no local branch exists. A missing ref is fetched before retrying.
An omitted ref (including Git shorthand) follows remote HEAD. Use commit hashes
for reproducibility; use `--repo-update` to request the latest branch tip.

## Manifest and synchronization boundaries

`workspace: {}` enables defaults: search `apps` and `packages`, and clone into
`packages`. The clone root is always searched too. Add other relative directories
to `search_roots` to discover repositories you already have, regardless of their
folder names. Paths are relative to the shared workspace root and must stay
inside it; symlink checkout locations are rejected.

Two matching local clones are ambiguous and produce an error. Narrow the search
and clone roots or move the extra clone. Repositories with the same basename
cannot both be cloned to the same destination; manually clone them under distinct
names within a search root. Existing directories are never overwritten to make
room for a different repository.

The tool reads direct Git declarations in `dependencies`, `dev_dependencies`,
and `dependency_overrides` from the consumer's pubspec. It does not recursively
read dependency pubspecs or resolve transitive dependencies. These three sections
are inspected as declarations, not evaluated as a Pub resolution graph; conflicting
refs for one repository must be reconciled before pull. Multiple packages using
one repository are checked out together and must use the same ref. `git.tag_pattern`
is not supported for managed packages; use an explicit ref or ignore the package.

Both commands refuse to manage the repository containing the consumer. Pull
checks dirty working trees and prepares refs/package paths before checkout changes.
A failed preparation leaves existing working files and HEADs intact, although Git
fetch metadata and newly created parent directories may remain. Applying changes
across repositories is not a single transaction: a disk, permission, or concurrent
edit failure during application can leave earlier repositories synchronized. Fix
the error and rerun. A failed command exits nonzero.

## Migration from the earlier prototype

- Keep `.dep-sync/manifest.yaml`, but remove `projects` and other repository-route
  lists. Replace them with `workspace` settings and optional `ignore_packages`.
- A `*.code-workspace` file alone no longer identifies the workspace root.
- `--melos-only` and `--skip-bootstrap` have been removed. SDK selection, Pub
  Workspace generation, override cleanup, and Melos bootstrapping are no longer
  part of either command.
- Existing generated files are left untouched. Review or remove old workspace
  configuration yourself before adopting your preferred local resolution setup.

## Development

```sh
dart pub get
dart format --output=none --set-exit-if-changed bin lib test example
dart analyze --fatal-infos
dart test
dart run example/local_demo.dart
dart pub publish --dry-run
```

CI runs integration tests with real local Git repositories on macOS, Linux, and
Windows, using both Dart 3.6.2 and the current stable Dart SDK. Publishing remains
a manual release step; see [RELEASING.md](https://github.com/yhhCh405/dep-sync/blob/main/RELEASING.md) in the repository.

## License

MIT. Copyright 2026 Ye Htet Hein. See [LICENSE](LICENSE).
