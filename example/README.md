# Example workspaces

These three workspaces demonstrate real Git dependency declarations over HTTPS,
with Flutter apps and shared package repositories. Each includes actual
pubspecs, minimal Dart source, and a `.dep-sync/manifest.yaml`.

| Workspace | Pattern |
| --- | --- |
| [example-workspace-1](example-workspace-1/README.md) | `standalone/shop_app` with one package per Git repository under `packages/`. |
| [example-workspace-2](example-workspace-2/README.md) | Two standalone apps sharing repositories that each contain several packages, declared using `git.path`, with Pub workspace generation enabled. |
| [example-workspace-3](example-workspace-3/README.md) | `products/`, `demos/`, and `libraries/` instead of conventional folder names; nested apps, renamed clones, and an ignored dependency. |

Start with a workspace README for its folder tree and commands. The `your-org`
URLs and commit hashes are illustrative placeholders, not hosted demo repositories. Replace them with
your team's actual repositories and commit hashes. Copy a workspace outside this source
repository and use real Git clones as described in its README. The included
package source shows the intended contents; it is not an initialized checkout.

Folder names are configurable: `standalone`, `mini_apps`, and `packages` are
examples rather than reserved names. The nearest ancestor containing
`.dep-sync/manifest.yaml` identifies the workspace; `search_roots` controls where
existing repositories are found and `default_clone_root` controls new clones.
Use `--cwd` to select an app from elsewhere. Commands process that app's direct
Git declarations, not every app or transitive dependency in the workspace.

## Automated local smoke demo

For an immediately runnable check without remote credentials, run from the
dep_sync source root:

```sh
dart pub get
dart run example/local_demo.dart
```

This separate script creates local Git fixtures temporarily, checks pull and
push, and removes them afterward. Its local URLs are test fixtures; the three
workspace templates above demonstrate the remote URLs used in team projects.

See the [main README](../README.md) for installation and the full command reference.

The manifests include schema modelines for VS Code YAML hover help in this
source checkout. When copying a workspace elsewhere, copy
`schema/manifest.schema.json` from the source root into the new workspace's
`.dep-sync/` folder and change its modeline to
`# yaml-language-server: $schema=./manifest.schema.json`.
