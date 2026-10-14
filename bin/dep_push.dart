import 'package:dep_sync/src/cli/dep_sync_cli.dart';

/// Provides the push alias, handling its version flag before delegating to the CLI.
Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && {'--version', '-v'}.contains(arguments.single)) {
    print('dep-push version $packageVersion');
    return;
  }
  await runDepSync(['push', ...arguments]);
}
