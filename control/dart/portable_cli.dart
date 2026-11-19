import 'dart:async';
import 'dart:convert';

import 'control_dispatcher.dart';
import 'control_commands.dart';
import 'managed_command.dart';

/// Validates the command group and flag advertised by `legion_cli --help`.
String? validatePortableCliHelp(String help) {
  if (utf8.encode(help).length > 64 * 1024 || help.contains('\u0000')) {
    return 'Installed legion_cli --help returned invalid or excessive output.';
  }
  final tokens = _tokens(help);
  if (!tokens.contains('--donotexpecthwmon')) {
    return 'Installed legion_cli did not advertise --donotexpecthwmon.';
  }
  for (final group in RegExp(r'\{([^}]*)\}').allMatches(help)) {
    final commands = _tokens(group.group(1)!);
    if (!commands.contains('set-feature')) continue;
    for (final command in interactiveCliCommands) {
      if (!commands.contains(command)) {
        return 'Installed legion_cli is missing command: $command';
      }
    }
    return null;
  }
  return 'Installed legion_cli did not report its supported commands.';
}

/// Runs qualification and cancels it when either session endpoint closes.
class QualificationResult {
  const QualificationResult(this.success, [this.reason]);
  final bool success;
  final String? reason;
}

Future<QualificationResult> qualifyPortableCli({
  required ExecuteCommand execute,
  required String cli,
  required bool Function() sessionIsAlive,
}) async {
  if (!sessionIsAlive()) {
    throw StateError('The app session ended before CLI qualification.');
  }
  final operation = execute(cli, const ['--help'], 3);
  Timer? watcher;
  var ended = false;
  try {
    watcher = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!ended && !sessionIsAlive()) {
        ended = true;
        operation.cancel();
      }
    });
    final result = await operation.result;
    if (ended || !sessionIsAlive()) {
      throw StateError('The app session ended during CLI qualification.');
    }
    if (result.status != ManagedCommandStatus.success ||
        result.exitStatus != 0) {
      return QualificationResult(
        false,
        'legion_cli --help failed: ${result.error.isEmpty ? result.exitStatus : result.error}',
      );
    }
    final reason = validatePortableCliHelp(
      utf8.decode(result.output, allowMalformed: true),
    );
    return QualificationResult(reason == null, reason);
  } finally {
    watcher?.cancel();
  }
}

Set<String> _tokens(String value) =>
    RegExp(r'[A-Za-z0-9_-]+')
        .allMatches(value)
        .map((match) => match.group(0)!)
        .toSet();
