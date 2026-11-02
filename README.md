# dep_sync

**Clone the Git packages your app needs, check out the right versions, and save
package changes back to your app's `pubspec.yaml`.**

dep_sync is a command-line tool for Dart and Flutter teams that keep an app and
its shared packages in separate Git repositories. Install it once, then run
`dep-sync pull` or `dep-sync push` from your app's folder.

## A workspace example

Imagine you work on a shopping app with two shared packages. Each folder below
is a separate Git repository:

```text
shop_workspace/
├── apps/
│   └── shop_app/            # Flutter app
│       └── pubspec.yaml
└── packages/
    ├── shared_widgets/      # Shared UI package
    │   └── pubspec.yaml
    └── auth_client/         # Login package
        └── pubspec.yaml
```

The app declares the packages as Git dependencies in
`apps/shop_app/pubspec.yaml`:

```yaml
dependencies:
  shared_widgets:
    git:
      url: git@github.com:your-org/shared_widgets.git
      ref: a12bc34de56f7890123456789abcdef012345678
  auth_client:
    git:
      url: git@github.com:your-org/auth_client.git
      ref: b23cd45ef67890123456789abcdef01234567890
```

Here, `ref` pins an exact Git commit. The URLs and hashes above are illustrative
placeholders; replace them with your repositories and actual commit hashes.

### What goes wrong without synchronization?

- **Joining the project:** you must find and clone every package repository,
  then check out the versions the app expects.
- **Switching app branches:** the app may now require `shared_widgets` at
  a specific commit, while your local copy still contains code from another release.
- **Sharing a package fix:** after committing changes in `auth_client`, you
  must copy its commit hash into the app's pubspec so teammates use that fix.

`flutter pub get` downloads Git dependencies into Pub's cache. It does not keep
these separate, editable repositories in sync with your app.

### What does dep_sync do?

| Run from `apps/shop_app` | Result |
| --- | --- |
| `dep-sync pull` | Reads the app's Git dependencies, clones missing repositories into `packages/`, and checks out their declared refs. Reuses existing repositories by matching their Git origin URL. |
| `dep-sync push` | Reads the current commits in the local package repositories and writes those commit hashes into the app's Git dependency `ref` fields. |

**`dep-sync push` saves commit hashes in the pubspec.** Upload package commits
with `git push` so teammates can fetch them.

## Install

You need Dart **3.6 or later within Dart 3**, Git, and access to the package
repositories. macOS, Linux, and Windows are supported.

```sh
dart pub global activate dep_sync
dep-sync --version
```

This is a globally installed CLI; you do not need to add it to your app's
`dependencies`.

The CLI declares `sdk: ^3.6.0` (`>=3.6.0 <4.0.0`). Published packages must include
an SDK upper bound, and our current dependencies also constrain their Dart SDKs
to versions below 4. Future major support requires dependency compatibility and
validation. Generated workspace roots use `publish_to: none` and do not impose
an upper SDK bound of their own.

The app you synchronize can use a different, older SDK when Pub workspace
generation is disabled; its SDK constraint is preserved.

Both `dart` and the Pub cache's executable directory must be on `PATH`. The
default executable directory is `$HOME/.pub-cache/bin` on macOS/Linux and
`%LOCALAPPDATA%\Pub\Cache\bin` on Windows. A custom `PUB_CACHE` changes it.
If a launcher reports `dart: command not found`, add your Dart SDK's `bin`
directory to `PATH`; a shell alias such as `dart="fvm dart"` is insufficient.

To install a local checkout of this tool instead, run
`dart pub global activate --source path .` from the dep_sync source directory.

## Set up and pull your packages

### 1. Put your app under a shared parent folder

Start with your app cloned into `shop_workspace/apps/shop_app`. The `packages`
folder can be empty; dep_sync will clone missing dependencies there.

### 2. Add the workspace configuration

Create `shop_workspace/.dep-sync/manifest.yaml` with this content:

```yaml
workspace:
  search_roots:
    - apps
    - packages
  default_clone_root: packages

ignore_packages: []
```

Your starting layout is now:

```text
shop_workspace/
├── .dep-sync/
│   └── manifest.yaml        # Where to find and clone repositories
├── apps/
│   └── shop_app/
│       └── pubspec.yaml     # Which Git packages and versions the app needs
└── packages/               # Empty, or contains your existing clones
```

`search_roots` lists folders to search for existing repositories.
`default_clone_root` is where missing repositories are cloned. All paths are
relative to `shop_workspace`. Keep the dependency list in the app's pubspec;
the manifest only configures locations and optional exclusions.

### 3. Run pull from the app folder

With Git dependencies declared as in the example above, run:

```sh
cd shop_workspace/apps/shop_app
dep-sync pull
```

The tool finds `.dep-sync/manifest.yaml` by looking up through parent folders.
On a successful first run, both repositories are checked out at their declared
commit hashes, giving you the workspace shown above.
Existing matching clones are reused. Uncommitted changes are protected by default.

Pull checks out a **detached HEAD**: the selected commit is checked out without
moving an existing local branch. Before editing a dependency, create a branch
there, for example `git switch -c fix-login`.

For a package inside a larger repository, add `path` under its `git` declaration,
for example `path: packages/auth_client`. dep_sync clones the repository and
checks that the package exists at that path.

### 4. Use the local packages while developing

With the default `use_resolution_workspace: false`, your app still resolves Git
dependencies through Pub's cache after a pull. To
make Flutter use your editable local copies, you can create
`apps/shop_app/pubspec_overrides.yaml` yourself:

```yaml
dependency_overrides:
  shared_widgets:
    path: ../../packages/shared_widgets
  auth_client:
    path: ../../packages/auth_client
```

Then run `flutter pub get` from `apps/shop_app` (`dart pub get` for a Dart app).
Local edits in those package folders can now be used by the app. Keep this
machine-local override file out of version control if that is your team's policy.
Remove or update the overrides when you want to use the declared Git versions again.

For a shared Pub workspace instead of path overrides, enable
`workspace.use_resolution_workspace` as described below. You continue to run
your normal package resolution, Flutter/FVM, and Melos commands yourself.

## Example: share a login fix with your team

Starting from `shop_workspace/apps/shop_app`:

```sh
cd ../../packages/auth_client
git switch -c fix-login
# Edit the package, then commit the files you changed.
git add .
git commit -m "Fix login"
git push -u origin fix-login

cd ../../apps/shop_app
dep-sync push
git diff -- pubspec.yaml
```

For example, if the login fix is commit
`0123456789abcdef0123456789abcdef01234567`, its declaration changes from:

```yaml
  auth_client:
    git:
      url: git@github.com:your-org/auth_client.git
      ref: b23cd45ef67890123456789abcdef01234567890
```

To:

```yaml
  auth_client:
    git:
      url: git@github.com:your-org/auth_client.git
      ref: 0123456789abcdef0123456789abcdef01234567
```

`dep-sync push` pins **all managed Git dependencies**, including `shared_widgets`,
to their current local commits. Keep their working trees clean and review the
whole pubspec diff. Refresh the app's lockfile with your normal Pub workflow when
appropriate, then commit and push the app changes using Git.

After teammates pull the updated app with Git, they run `dep-sync pull` from its
folder to check out the same package commits. Commit hashes keep this handoff
reproducible; branch names can move over time.

## Optional Pub workspace generation

If your app declares `resolution: workspace`, Pub needs an ancestor pubspec that
lists it as a workspace member. Enable generation in `.dep-sync/manifest.yaml`:

```yaml
workspace:
  search_roots: [packages]
  default_clone_root: packages
  use_resolution_workspace: true
ignore_packages: []
```

After a successful `dep-sync pull`, a new root `pubspec.yaml` might contain:

```yaml
# Generated by dep-sync. Do not edit manually.
name: dep_sync_workspace
publish_to: none
environment:
  sdk: '>=3.6.0'
workspace:
  - standalone/customer_app
  - packages/flutter-core/core_interface
  - packages/flutter-core/core_utils
```

Generation includes the selected app, its managed Git packages, local path
dependencies recursively, and explicit nested `workspace` members. A repository
with several packages contributes their package paths, not its repository root.
Nested members are listed only by their parent. Paths must remain inside the
shared workspace. Workspace globs are not expanded; use explicit member paths.
Git synchronization still manages only the selected app's direct Git declarations;
workspace generation does not fetch additional transitive Git repositories.

Every member must declare a Dart SDK lower bound of at least 3.6.0. Incompatible
SDK constraints, duplicate package names, unsafe paths, and user-file conflicts
abort preparation before existing checkouts move. SDK constraints and package
pubspecs are never rewritten. Where a package lacks `resolution: workspace`,
dep_sync creates a `pubspec_overrides.yaml` containing that setting.

An existing user root pubspec is preserved and must already list the required
members. Existing user overrides are also preserved; if they need a resolution
setting, add `resolution: workspace` yourself. Errors identify the conflicting
file or missing members. A compatible existing workspace can be reused.

Run `flutter pub get` yourself after pulling (`dart pub get` for Dart-only
workspaces). Pub resolves member dependencies to their local workspace copies,
including dependencies declared with Git sources, so those members need no path
overrides. Ignored Git dependencies are not added automatically and remain under
your team's control. A local path dependency on an ignored package is rejected.

The setting defaults to **false**, which retains checkout-only behavior. Setting
it back to false leaves generated files in place; it does not automatically undo
your Pub setup. Generated file contents are recorded in
`.dep-sync/pub-workspace-state.json`. Keep that local state alongside generated
files; do not edit generated files directly. Edited files cause a conflict instead
of being overwritten. A later pull updates the generated root for the selected
app and removes stale, unchanged generated overrides (excluded packages are left
alone). Avoid concurrent pulls against a shared workspace.

Exact untracked resolution overrides generated by dep_sync do not block ordinary
pull/push. Edited or tracked changes remain protected. `--fresh` still treats
these files as local data and requires `--force` to discard and regenerate them.
Checkout application and workspace file application are separate stages: a disk
or concurrent-edit failure after checkout can require fixing the error and rerunning.

See [workspace 2](example/example-workspace-2/README.md) for the complete layout.

## Manifest hover help in VS Code

Install the [Red Hat YAML extension](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml).
The bundled [manifest schema](schema/manifest.schema.json) provides hover help,
completion, defaults, and validation for each manifest field.

In a source checkout, the repository's VS Code settings associate the schema with
`**/.dep-sync/manifest.yaml`; the example manifests also include local schema
modelines. For your own workspace, copy `schema/manifest.schema.json` into
`.dep-sync/manifest.schema.json` and put this at the top of your manifest:

```yaml
# yaml-language-server: $schema=./manifest.schema.json
workspace:
  search_roots: [packages]
  default_clone_root: packages
  use_resolution_workspace: true
ignore_packages: []
```

Hover over `use_resolution_workspace` to see its behavior and requirements. The
schema association is an editor comment; it does not add a manifest property.
A globally activated package also bundles the schema under its package directory
in the Pub cache. No VS Code configuration is required to run the CLI.

## More workspace layouts

See the [three example workspaces](example/README.md) for actual manifests,
app pubspecs, and package source:

- [Standalone app and package repositories](example/example-workspace-1/README.md).
- [Multiple apps and packages inside shared repositories](example/example-workspace-2/README.md), using `git.path`.
- [Nested apps and custom search/clone roots](example/example-workspace-3/README.md), including renamed checkouts and ignored dependencies.

`apps/` and `packages/` are defaults, not required folder names. For example,
a team using `products/`, `demos/`, and `libraries/` can configure:

```yaml
workspace:
  search_roots:
    - libraries/shared
    - libraries/features
    - products
    - demos
  default_clone_root: libraries/vendor
ignore_packages: []
```

Run from the selected app or pass its path with `--cwd`. Each invocation manages
one app's direct Git declarations. Repository locations must remain inside the
workspace; the clone root is also searched automatically.

For an automated check using temporary local Git fixtures, run
`dart run example/local_demo.dart` from this tool's source checkout.

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

`dep-pull` and `dep-push` print this notice before their command output:

```text
╭────────────────────────────────────────────────────────────╮
│                          DEP-SYNC                          │
│   Git Multi-Repos Workspace Dependencies Synchronization   │
╰────────────────────────────────────────────────────────────╯
```

Color-capable terminals show a bold cyan title and muted borders/subtitle.
Redirected output and terminals with `NO_COLOR` set omit color codes.

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
and `dependency_overrides` from the consumer's pubspec for Git synchronization.
It does not recursively synchronize transitive Git dependencies. Optional Pub
workspace generation separately follows local path dependencies and nested members. These three sections
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
- `--melos-only` and `--skip-bootstrap` have been removed. Use the optional
  `workspace.use_resolution_workspace` manifest setting for Pub workspace setup.
  SDK selection and Melos bootstrapping remain outside the CLI.
- Older generated files without this version's ownership state are treated as
  user configuration. Review them before enabling workspace generation.

## Development

The source separates CLI parsing, synchronization use cases, and infrastructure
adapters. Classes and methods include Dart documentation comments describing
purpose, usage, side effects, and failure behavior.

External operations have explicit contracts:

- `GitOperations` defines repository operations used by pull, push, and discovery;
  `GitClient` implements them with command-line Git.
- `PubspecStore` defines declaration reads and complete ref updates;
  `PubspecRepository` implements YAML preservation and atomic replacement.
- `ProcessExecutor` defines command execution; `ProcessRunner` implements it
  through Dart processes without shell interpolation.

Both use cases accept `git` and `pubspecs` constructor arguments, and `GitClient`
accepts a `runner`. Defaults use the production adapters. Tests can inject
substitutes at these boundaries without inheriting concrete implementations.

```sh
dart pub get
dart format --output=none --set-exit-if-changed bin lib test example
dart analyze --fatal-infos
dart test
dart run example/local_demo.dart
dart pub publish --dry-run
```

CI runs integration tests with real local Git repositories on macOS, Linux, and
Windows, using both Dart 3.6.2 and the current stable Dart SDK. Successful main
builds tag unpublished package versions; validated tag builds publish to pub.dev.
See [RELEASING.md](https://github.com/yhhCh405/dep-sync/blob/main/RELEASING.md) for
the required trusted-publishing and release-token setup.

## License

MIT. Copyright 2026 Ye Htet Hein. See [LICENSE](LICENSE).
