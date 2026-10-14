import 'package:dep_sync/src/cli/dep_sync_cli.dart';

/// Runs the main CLI dispatcher with the supplied command-line arguments.
Future<void> main(List<String> arguments) async {
  await runDepSync(arguments);
}
