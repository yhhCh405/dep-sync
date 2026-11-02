# Example 2: Multiple packages in each repository

```text
example-workspace-2/
├── .dep-sync/manifest.yaml
├── standalone/
│   ├── customer_app/pubspec.yaml
│   └── merchant_app/pubspec.yaml
└── packages/
    ├── flutter-core/             # One Git repository
    │   ├── core_interface/pubspec.yaml
    │   └── core_utils/pubspec.yaml
    └── payment-feature/          # Another Git repository
        ├── payment_ui/pubspec.yaml
        └── payment_utils/pubspec.yaml
```

This follows a common Flutter multi-repository pattern: each feature repository
contains multiple Dart packages. The customer app declares both packages from
`flutter-core.git` using the same URL and ref, with `path: core_interface` or
`path: core_utils`. The payment packages work the same way.

A `git.path` is relative to the root of its remote repository, not to the app or
workspace. Pull clones each repository only once and validates each package path.
All managed declarations for the same repository must agree on the ref.

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
cd standalone/customer_app
dep-sync pull
dep-sync push
```

The merchant app shares the core packages but does not declare the payment
packages. Run its commands separately with `--cwd standalone/merchant_app` from
the workspace root. dep_sync reads one consuming app per command; it does not
synchronize every app automatically. Avoid running commands concurrently against
shared checkouts. Switching between apps that declare different refs switches
the shared repository checkout to the selected app's ref.

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
