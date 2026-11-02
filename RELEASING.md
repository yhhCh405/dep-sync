# Releasing dep_sync

## One-time configuration

Pub.dev permits GitHub OIDC publishing only from tag-triggered workflow runs.
The CI pipeline therefore validates main, creates a version tag, and publishes
from the validated tag build. See the [official requirements](https://dart.dev/tools/pub/automated-publishing).

1. As the package uploader or publisher admin, enable publishing from GitHub
   Actions in [the package admin page](https://pub.dev/packages/dep_sync/admin).
   Set repository `yhhCh405/dep-sync` and tag pattern `v{{version}}`. The workflow
   does not specify a GitHub environment; leave that optional requirement unset,
   or configure matching environments on both sides if your team needs one.
2. Create a repository secret named `RELEASE_TOKEN`: a fine-grained personal
   access token scoped to this repository with Contents read/write permission.
   Tags pushed with the default `GITHUB_TOKEN` do not trigger another workflow;
   this separate token is required for the tag build to start. Never commit it.
   Use an appropriate expiry and rotate it according to your team's policy.

These account-level settings must be configured separately from merging the PR.
If a new version needs releasing and the token is absent, the main release-tag
job fails with setup instructions. Tests do not require this secret.

## Release through a reviewed PR

1. Update `version` in `pubspec.yaml`, `packageVersion` in
   `lib/src/cli/dep_sync_cli.dart`, and `CHANGELOG.md` together. The CLI test checks
   the version fields agree. Each new release requires a new package version;
   ordinary documentation/code pushes with an already-published version are skipped.
2. Run the checks documented in README and review `dart pub publish --dry-run`.
3. Open a PR to `main` and review it. Merging/pushing to main runs the test matrix
   on macOS, Linux, and Windows with Dart 3.6.2 and stable.
4. After the entire matrix succeeds, the release-tag job checks the exact version
   on pub.dev. Only a 404 means an unpublished version. Network/server errors
   fail instead of being interpreted as permission to release.
5. For an unpublished version, CI creates `v<version>` at that main commit using
   `RELEASE_TOKEN`. Tags are immutable; an existing tag causes an actionable failure.
6. The tag push triggers CI again. After its matrix passes, the publish job verifies
   the tag matches the pubspec and its commit is in main history, obtains an OIDC
   token through setup-dart, runs the publication dry run, and publishes.

Failed publishing runs can be rerun from the tag's GitHub Actions run after fixing
account configuration. Never move a published version tag. A dry run cannot verify
uploader ownership or server-side authorization. No actual publication occurs on
feature branch pushes or pull requests.

## Manual recovery

An authorized uploader can still publish a reviewed, validated release using
`dart pub publish` from its clean release commit. Reconcile its version tag with
the published commit. Do not overwrite an existing release or bump versions merely
to work around failing tests.
