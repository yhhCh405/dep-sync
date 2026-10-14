# Releasing dep_sync

The public repository is https://github.com/yhhCh405/dep-sync. The package uses
MIT with Ye Htet Hein as its copyright holder. Release from this Dart package;
do not include private repositories, credentials, or internal operational files.

1. Set the release version in `pubspec.yaml`, update `packageVersion` in
   `lib/src/cli/dep_sync_cli.dart`, and add the matching `CHANGELOG.md` entry.
   The CLI test checks that `packageVersion` matches `pubspec.yaml`.
2. Run `dart pub get`, `dart analyze --fatal-infos`, `dart test`, and
   `dart run example/local_demo.dart`. Check formatting with the command in README.
3. Check the GitHub Actions matrix for the exact release commit on all platforms
   and both supported SDK test versions.
4. Run `dart pub publish --dry-run`; require zero warnings and inspect the archive.
5. Smoke-test global activation in an isolated `PUB_CACHE` and all three commands.
6. Commit and push the release source. Ensure the working tree is clean.
7. As the authorized package uploader, run `dart pub publish`, review the final
   archive and authenticate if required. This is a separate action from git push.
8. After successful publication, tag the published commit `v<version>` and push
   that tag. Verify installation from pub.dev in a clean environment.

Publication is intentionally not triggered by pushing to this repository.
A dry run cannot confirm package-name ownership or server-side upload permission.
