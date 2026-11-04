<div align="center">

# dep_sync

### Keep your Flutter & Dart Git dependencies in sync.

**Clone the right repositories. Check out the right commits. Share changes without copying Git hashes by hand.**

[![pub package](https://img.shields.io/pub/v/dep_sync.svg)](https://pub.dev/packages/dep_sync)
[![pub points](https://img.shields.io/pub/points/dep_sync)](https://pub.dev/packages/dep_sync/score)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows-informational)](https://pub.dev/packages/dep_sync)

[**Get started**](#quick-start) · [**See the workflow**](#how-it-works) · [**Configuration**](#configuration) · [**Examples**](example/README.md)

</div>

---

## Why dep_sync?

If your Flutter app depends on packages stored in **separate Git repositories**, keeping an editable local workspace aligned with `pubspec.yaml` gets repetitive:

- Clone each package repository manually.
- Check out the exact commit required by your app after switching branches.
- Copy new commit hashes into `pubspec.yaml` when a package changes.
- Repeat the process for teammates and across projects.

`flutter pub get` resolves Git dependencies into Pub's cache; it doesn't maintain your **separate, editable Git checkouts**.

`dep_sync` maintains those editable checkouts. Your app's `pubspec.yaml` remains the source of truth for dependency versions, while a small workspace manifest tells the CLI where your repositories live.

| Command | What it does |
| --- | --- |
| `dep-pull` | Find or clone your app's direct Git dependencies, then check out their declared refs. |
| `dep-push` | Pin local dependency commits in the app's `pubspec.yaml` and refresh its `dep-sync.lock` run receipt. |

> **Important:** `dep-push` updates `pubspec.yaml`; it does **not** run `git push` or publish your packages. Commit and push package changes with Git first.

Use **`dep-pull`** and **`dep-push`** for daily work, or the equivalent `dep-sync pull` and `dep-sync push` subcommands.

## Built for multi-repository Flutter teams

The motivating use case is a workspace with **multiple Flutter apps** and **multiple Dart packages per Git repository**. For example:

```text
workspace/
├── .dep-sync/manifest.yaml
├── standalone/
│   ├── customer_app/pubspec.yaml
│   └── merchant_app/pubspec.yaml
└── packages/
    ├── flutter-core/            # One Git repository
    │   ├── core_interface/pubspec.yaml
    │   └── core_utils/pubspec.yaml
    └── payment-feature/         # Another Git repository
        ├── payment_ui/pubspec.yaml
        └── payment_utils/pubspec.yaml
```

Each app declares the Git packages it needs in its own `pubspec.yaml`. Packages in the same repository share a Git URL and commit hash, with `git.path` identifying the package inside that repository. **dep_sync checks out each repository once** and keeps its local commit aligned with the selected app's declarations.

This is illustrated in [Example 2: multiple packages per repository](example/example-workspace-2/README.md), including optional Pub workspace generation. The examples are templates using placeholder remotes, not live repositories.

## Quick start

### 1. Install

Requires **Dart 3.6 or later, below 4.0**, Git, and access to your Git repositories. Supports macOS, Linux, and Windows.

```bash
dart pub global activate dep_sync
dep-sync --version
```

Ensure Dart and Pub's global executable directory are on `PATH`. The default executable directory is `$HOME/.pub-cache/bin` on macOS/Linux and `%LOCALAPPDATA%\Pub\Cache\bin` on Windows; a custom `PUB_CACHE` changes this location. You don't need to add `dep_sync` to your app dependencies.

The CLI's SDK requirement is independent of the app it synchronizes. Older app SDK constraints are preserved when Pub workspace generation is disabled.

<details>
<summary><strong>Installing from source or troubleshooting PATH</strong></summary>

From a checkout of this repository, run `dart pub global activate --source path .`.

If `dep-pull` reports `dart: command not found`, add your Dart SDK's `bin` directory to `PATH`. A shell alias such as `dart="fvm dart"` cannot be used by Pub's executable launcher.

</details>

### 2. Declare Git dependencies

For example, in `apps/shop_app/pubspec.yaml`:

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

*The repository URLs and commit hashes above are placeholders.*

### 3. Create a workspace manifest

Create `.dep-sync/manifest.yaml` at the shared workspace root:

```yaml
workspace:
  search_roots: [apps, packages]
  default_clone_root: packages
ignore_packages: []
```

Start with this layout (the `packages/` directory can be empty):

```text
shop_workspace/
├── .dep-sync/
│   └── manifest.yaml
├── apps/
│   └── shop_app/
│       └── pubspec.yaml
└── packages/
```

### 4. Pull the declared versions

```bash
cd shop_workspace/apps/shop_app
dep-pull
```

The CLI searches the configured roots for matching Git origins, reuses existing checkouts, clones missing repositories, and checks out the declared refs.

```text
shop_workspace/
├── .dep-sync/manifest.yaml
├── apps/shop_app/pubspec.yaml
└── packages/
    ├── shared_widgets/   # checked out at the declared ref
    └── auth_client/      # checked out at the declared ref
```

Pull normally checks out commits in **detached HEAD** state. Create a branch inside a package before making changes (for example, `git switch -c fix-login`). Dirty checkouts are protected by default.

## How it works

```text
             App: pubspec.yaml
          (Git URLs + pinned refs)
                     │
             dep-pull
                     ▼
        Local package Git clones
          (checkout matching refs)
                     │
          edit → commit → git push
                     │
             dep-push
                     ▼
             App: pubspec.yaml
          (updated commit hashes)
```

### Share a package change

```bash
# From shop_workspace/apps/shop_app
cd ../../packages/auth_client
git switch -c fix-login
# Edit and test the package.
git add .
git commit -m "Fix login"
git push -u origin fix-login

cd ../../apps/shop_app
dep-push
git diff -- pubspec.yaml
```

`dep-push` pins **every managed Git dependency** to its current local commit, not just the package you edited. Review the entire diff, keep all managed dependency working trees clean, run your usual `flutter pub get` if needed, then commit and push the app changes separately. Your teammates can run `dep-pull` after updating their app checkout.

### The dep-push run receipt

Every successful `dep-push` creates or refreshes `dep-sync.lock` beside the
selected app's pubspec, even if its refs are already pinned or it has no managed
Git dependencies. Commit this receipt with the app's pubspec changes:

```yaml
# Generated by dep-push. Do not edit manually.

lock_version: 1

last_dep_push:
  completed_at_utc: "2026-11-03T02:30:00Z"
  tool_version: "0.2.2"
```

The receipt records the last successful run; dependency commits remain in the
pubspec. Validation or pubspec-save failures leave the previous receipt unchanged.
Both files are replaced atomically individually. If saving the receipt fails
following a successful pubspec save, the command reports that refs were saved and
asks you to fix the error and rerun `dep-push`.

### Develop against the local copies

By default, `pull` **checks out repositories** but does not change how Pub resolves your app's Git dependencies. To use local source while developing, you can add `apps/shop_app/pubspec_overrides.yaml`:

```yaml
dependency_overrides:
  shared_widgets:
    path: ../../packages/shared_widgets
  auth_client:
    path: ../../packages/auth_client
```

Then run `flutter pub get` (or `dart pub get`). Keep local overrides out of version control if that is your team's policy, and remove or update them when returning to the declared Git versions. Alternatively, enable [optional Pub workspace generation](#optional-pub-workspace-generation) for a shared workspace. Without native workspace mode, dep_sync does not run Flutter, FVM, Pub, or Melos commands.

## Configuration

`.dep-sync/manifest.yaml` describes **repository locations** and workspace behavior. Dependency versions stay in the app's pubspec:

```yaml
workspace:
  search_roots:
    - apps
    - packages
  default_clone_root: packages
  use_resolution_workspace: false

ignore_packages:
  - experimental_sdk
```

| Field | Purpose |
| --- | --- |
| `workspace.search_roots` | Relative directories searched recursively for existing clones. Defaults to `[apps, packages]`. |
| `workspace.default_clone_root` | Parent directory for missing clones. Defaults to `packages` and is also searched automatically. |
| `workspace.use_resolution_workspace` | Opt in to generating Dart Pub workspace configuration after a successful pull. Defaults to `false`. |
| `ignore_packages` | Exact dependency names to leave unmanaged. |

`workspace: {}` uses the default search roots `apps` and `packages`, and the default clone root `packages`. Run commands from an app directory or pass `--cwd <path>`. The CLI finds the nearest manifest by walking up parent directories. Paths are relative to the workspace root, not the manifest's `.dep-sync/` folder.

Folder names are configurable. You can use `standalone/` and `packages/`, or names such as `products/`, `libraries/`, and `demos/`; see [Example 3](example/example-workspace-3/README.md).

### Editor hover help and completion

The [manifest JSON Schema](schema/manifest.schema.json) provides field descriptions, completion, and validation with the [Red Hat YAML extension](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml).

Automatic detection for `**/.dep-sync/manifest.yaml` has been submitted to [SchemaStore](https://github.com/SchemaStore/schemastore/pull/6582). Once that contribution is merged and published, editors using an up-to-date SchemaStore catalog can recognize the manifest without a schema comment or custom association.

For immediate or offline use, copy `schema/manifest.schema.json` into your workspace's `.dep-sync/` folder and add this first line to the manifest:

```yaml
# yaml-language-server: $schema=./manifest.schema.json
```

In this source repository, `.vscode/settings.json` already associates the schema. Editor configuration is optional for running the CLI.

### Optional Pub workspace generation

If your app uses `resolution: workspace`, enable:

```yaml
workspace:
  search_roots: [packages]
  default_clone_root: packages
  use_resolution_workspace: true
ignore_packages: []
```

After a successful pull, dep_sync prepares the root Pub workspace and missing resolution overrides for the selected app, managed package paths, recursive local path dependencies, explicit nested members, and necessary ancestor packages. Packages declared through `git.path` are listed by their package paths. Nested members are listed only through their parent. Use explicit member paths; workspace globs are not expanded.

Native workspace pulls now run Pub resolution automatically. Consumer FVM pins (`.fvmrc` or `.fvm/fvm_config.json`) take precedence over workspace pins; FVM installs the pinned SDK and runs `flutter pub get --no-example`. Without a pin, Flutter workspaces use `flutter` on PATH and pure Dart workspaces use the running Dart SDK. Use `--skip-pub-get` to prepare checkouts and configuration only. Progress is reported every 10 seconds and output is saved to `.dep-sync/pub-get.log`. Pub resolves workspace member dependencies to their local copies, including dependencies declared with Git sources; those members do not need separate path overrides.

<details>
<summary><strong>Workspace generation requirements and file ownership</strong></summary>

- Every member needs a Dart SDK lower bound of at least 3.6.0, and members must have compatible SDK constraints and unique names. Package SDK constraints are never rewritten.
- Existing user-maintained root pubspecs must already list the required members. Existing user overrides are preserved; add `resolution: workspace` yourself if a conflicting override needs it.
- Generated-file ownership is recorded in `.dep-sync/pub-workspace-state.json`. Keep that state with generated files. Edited generated files produce a conflict instead of being overwritten.
- A later pull updates generated membership for the selected app and removes stale, unchanged generated overrides. It does not include every app in the workspace automatically. Excluded packages are left alone.
- This mode does not fetch transitive Git dependencies. A local path dependency on an ignored package is rejected.
- Untracked legacy `melos.yaml` generated by the shell tool is backed up to `.dep-sync/legacy-melos.yaml` and removed when it generates incompatible package overrides. Tracked or customized legacy configuration requires manual migration. Native resolution does not invoke Melos; use Melos 7 with workspace-compatible configuration if you need Melos scripts.
- Turning the setting off leaves generated configuration in place. It does not undo the Pub workspace setup.
- Pub forbids `dependency_overrides` for packages that are also workspace members, even when the override points to the same local folder. Workspace generation checks these conflicts before checkout.
- Untracked files with the Melos `melos_managed_dependency_overrides` marker can be migrated entry by entry. Only paths that point exactly to selected workspace members are redundant; version pins and paths to non-members are preserved. Extra fields/comments, tracked or staged files, and ordinary user override files are protected.
- Pub allows each dependency to be overridden only once across a workspace. Identical duplicate pins in eligible Melos-generated files are consolidated at the generated root. Paths are compared by their resolved package directories and rewritten relative to the root. Different versions or targets produce a conflict; protected files are not rewritten. An existing user root must already contain the matching shared override, otherwise manual configuration is required.
- The state file records centralized overrides and their origins. Repeated pulls keep them for the selected app, and later edits to origin files require reconciliation rather than silently losing a pin. Preserve this state with the generated workspace configuration.
- An override's path alone does not add that package to the workspace. Overrides for non-members remain intact.
- Exact untracked resolution overrides generated by dep_sync do not block ordinary pull/push. Edited or tracked changes remain protected; `--fresh` still requires `--force` to discard generated local overrides.

</details>

See the [multi-package workspace example](example/example-workspace-2/README.md) for a complete setup.

## CLI reference

The `dep-pull` and `dep-push` aliases display a bordered DEP-SYNC notice with the subtitle **Git Multi-Repos Workspace Dependencies Synchronization**. Terminal color is disabled for redirected output and when `NO_COLOR` is set.

**Recommended everyday commands:**

```bash
dep-pull [options]
dep-push [options]
```

**Unified CLI alternatives:**

```bash
dep-sync pull [options]
dep-sync push [options]
dep-sync --help
dep-sync --version
```

Both commands support `--cwd <consumer-directory>` and `--verbose`; `DEP_SYNC_VERBOSE=1` enables verbose output.

| Pull option | Behavior |
| --- | --- |
| `--repo-update` | Fetch and use the remote tip for a declared branch ref; does not reset your local branch. |
| `--pull-branch` | Fetch and use the unique remote branch containing a commit or tag; fails if ambiguous. |
| `--fallback-branch <name>` | Use a fallback remote branch if the requested ref cannot be resolved; does not rewrite the declared ref. |
| `--force` | Discard local tracked changes and untracked files in managed checkouts. |
| `--fresh` | Prepare replacement clones before replacing existing ones, subject to safety checks. |

> **Destructive combination:** `--fresh --force` can discard ignored files and unpublished commits in replaced clones. Use it only for disposable checkouts.

<details>
<summary><strong>Safety guarantees and important boundaries</strong></summary>

- Manages **direct** Git declarations in `dependencies`, `dev_dependencies`, and `dependency_overrides`; it does not recursively fetch transitive Git dependencies.
- Multiple packages in one repository must agree on the Git ref. Package subdirectories can be declared with `git.path`.
- Does not manage the repository containing the selected app.
- Refuses dirty checkouts by default, ambiguous matching clones, unsafe destinations, and conflicting repository refs.
- Ignored dependencies are not cloned, fetched, checked out, or pinned. If ignored and managed packages share a repository, the command fails rather than partially managing that repository.
- A successful `push` preserves unrelated YAML content and checks for concurrent pubspec edits before atomic replacement.
- A failed preparation protects existing working files and HEADs, though fetch metadata or newly created parent folders may remain. Applying changes across multiple repositories is **not** one atomic transaction; rerun after fixing a disk, permission, or concurrent-edit failure.
- `git.tag_pattern` is not supported for managed packages; use an explicit ref or ignore the package.
- `--fresh` refuses worktrees, submodules, and nested Git repositories.

</details>

<details>
<summary><strong>More operational details</strong></summary>

- When a ref is omitted, the remote's default branch is used. Existing local branches normally resolve to their local tips; use `--repo-update` when you want the remote branch tip.
- Removing a Git declaration stops management of that dependency but does not delete its local clone.
- Regular hosted, SDK, and path dependencies are not changed by Git synchronization.
- Package paths and checkout locations must stay within the workspace; symlink checkout locations are rejected. Multiple matching origins are ambiguous, and repositories with colliding clone names must be placed in distinct directories under a search root.
- Existing user Pub workspace configuration is kept intact. Generated overrides may be updated or removed only when their recorded contents remain unchanged. Avoid simultaneous pulls into the same workspace.
- Earlier prototype manifests using `projects`, the `--melos-only` or `--skip-bootstrap` flags, or only `*.code-workspace` identification must be migrated to the `workspace` manifest format.

</details>

## Examples

| Example | Best for | What it demonstrates |
| --- | --- | --- |
| **[Example 2: Multiple packages per Git repository](example/example-workspace-2/README.md)** | **Real-world multi-repo Flutter architectures** | Two apps, shared multi-package repositories, `git.path`, and optional Pub workspace generation. |
| [Example 1: One package per repository](example/example-workspace-1/README.md) | Getting started | An app using separate, single-package Git repositories. |
| [Example 3: Custom workspace layouts](example/example-workspace-3/README.md) | Advanced setups | Nested apps, renamed local clones, custom search roots, and ignored dependencies. |

These example directories are **templates**: replace placeholder URLs and commit hashes with accessible Git repositories before running them. For a self-contained test requiring no remote credentials, run from a source checkout:

```bash
dart pub get
dart run example/local_demo.dart
```

The demo creates temporary local Git fixtures and verifies the pull/push workflow.

## Development and contributing

The implementation separates CLI parsing, synchronization use cases, and infrastructure adapters. Git, pubspec, and process execution are injectable for testing. Contributions and bug reports are welcome through [GitHub Issues](https://github.com/yhhCh405/dep-sync/issues).

```bash
dart pub get
dart format --output=none --set-exit-if-changed bin lib test example
dart analyze --fatal-infos
dart test
dart run example/local_demo.dart
dart pub publish --dry-run
```

CI tests real local Git repository scenarios on macOS, Linux, and Windows with Dart 3.6.2 and stable. For publishing and version tagging, see [RELEASING.md](RELEASING.md).

## License

[MIT](LICENSE) © 2026 Ye Htet Hein.

---

<div align="center">

**Useful for your Flutter team?** [Explore on pub.dev](https://pub.dev/packages/dep_sync) · [Report an issue](https://github.com/yhhCh405/dep-sync/issues)

</div>
