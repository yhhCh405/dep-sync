# Example 1: One package per repository

```text
example-workspace-1/
├── .dep-sync/manifest.yaml
├── standalone/
│   └── shop_app/                 # App repository
│       ├── pubspec.yaml
│       └── lib/main.dart
└── packages/
    ├── shared_widgets/           # Repository: shared_widgets.git
    │   ├── pubspec.yaml
    │   └── lib/shared_widgets.dart
    └── auth_client/              # Repository: auth_client.git
        ├── pubspec.yaml
        └── lib/auth_client.dart
```

The app depends on two repositories over HTTPS. Each repository has its package
at the root, so its Git declaration needs only `url` and `ref`.

## Use this workspace

The files show the layout **after repositories have been cloned**. They are
source templates, not initialized Git repositories. All `your-org` URLs and
commit hashes are illustrative placeholders: replace them with accessible repositories and
actual commit hashes before running the commands. The package files illustrate what
belongs in those repositories; they are not copies of private production code.

Copy this workspace outside the dep_sync checkout. In your copy, replace each
sample app/package repository directory with a real clone in the same position.
Do not leave an uninitialized sample directory at a clone destination: pull will
refuse to overwrite it. Alternatively, remove the sample package directories and
let pull clone your real dependencies. Keep `.dep-sync/manifest.yaml` at the root.
For a repository containing multiple packages, clone the whole repository once,
rather than cloning each Dart package separately.

Install the tool with `dart pub global activate dep_sync`. Dart and Git must be
on `PATH`, and your Git credentials must allow access to the dependency remotes.
Flutter is needed to run the sample apps; dep_sync itself runs with Dart.

From this workspace root:

```sh
cd standalone/shop_app
dep-sync pull
dep-sync push
```

The manifest searches `packages/`. Missing repositories are cloned there using
their repository names. Pull checks out the declared commit hashes; push updates them to the current
local commit hashes.

Pull checks out detached HEADs and protects uncommitted changes by default.
Before editing a package, create a branch in its repository, commit the changes,
and upload them with `git push`. Then run `dep-sync push` from the app folder to
pin **all managed Git dependencies** to their current local commits. Review and
commit the app's pubspec changes. Push does not upload package commits.

Cloning packages does not redirect Flutter to those folders. Use your team's
path overrides or Pub workspace setup for local development, then run your normal
Pub/Flutter/Melos commands. dep_sync does not generate that configuration or select
an SDK. These templates omit platform scaffolding; they illustrate dependency
configuration rather than a complete generated Flutter application.
