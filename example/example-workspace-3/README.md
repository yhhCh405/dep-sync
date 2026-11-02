# Example 3: Nested apps and custom repository locations

```text
example-workspace-3/
├── .dep-sync/manifest.yaml
├── products/mobile/customer_app/pubspec.yaml
├── demos/checkout_demo/pubspec.yaml
└── libraries/
    ├── shared/
    │   └── company-foundation/   # Origin: flutter-core.git
    │       └── core_utils/pubspec.yaml
    ├── features/
    │   └── checkout/             # Origin: checkout-feature.git
    │       └── checkout_ui/pubspec.yaml
    └── vendor/
        └── analytics_client/    # Origin: analytics_client.git
            └── pubspec.yaml
```

Apps do not have to live in `apps/`, and repositories do not have to sit directly
under `libraries/`. The manifest searches nested roots and clones missing
repositories into `libraries/vendor`. Existing checkouts are matched by Git origin,
so the local names `company-foundation` and `checkout` can differ from remote
repository names. In real clones, their `origin` URLs must match the app's Git URLs.

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
dep-sync pull --cwd products/mobile/customer_app
dep-sync push --cwd products/mobile/customer_app
# Synchronize a different consumer separately:
dep-sync pull --cwd demos/checkout_demo
```

If `company-foundation` is missing, pull clones `flutter-core.git` into
`libraries/vendor/flutter-core`, rather than recreating its former custom folder.
The clone root is searched automatically as well as the listed search roots.

`external_sdk` is declared by the customer app but listed in `ignore_packages`.
It is not cloned, checked out, or pinned by dep_sync. Pub still resolves it normally.

All manifest paths must stay inside the shared workspace. Symlink checkout
locations and multiple matching clones are rejected. A package folder without a
Git repository and matching origin is not an existing checkout.

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
