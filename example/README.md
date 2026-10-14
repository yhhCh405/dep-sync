# Local multi-repository demonstration

From the dep_sync source directory, run:

```sh
dart pub get
dart run example/local_demo.dart
```

The script creates a temporary workspace and a local Git repository containing a
Dart package. It writes `.dep-sync/manifest.yaml`, pulls the dependency, and pins
its commit in an app pubspec. It verifies that the app's original SDK constraint
is retained, then removes the temporary fixture. No remote account, Flutter,
Melos, or package bootstrap is needed. Git must be on PATH.

For your own workspace, create `.dep-sync/manifest.yaml` at the shared parent:

```yaml
workspace:
  search_roots: [apps, packages]
  default_clone_root: packages
ignore_packages: []
```

Add or remove Git dependencies in the consuming app's `pubspec.yaml`, not in the
manifest. Use `ignore_packages` for dependencies you manage separately. See the
main README for installation, remote access, local development, and command flags.
