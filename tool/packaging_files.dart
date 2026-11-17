// Shared file and process operations for dependency-free packaging tools.
import 'dart:convert';
import 'dart:io';

ProcessResult _packagingProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  Encoding? stdoutEncoding = systemEncoding,
}) {
  final result = Process.runSync(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: environment == null,
    stdoutEncoding: stdoutEncoding,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return result;
}

String packagingCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) =>
    _packagingProcess(
          executable,
          arguments,
          workingDirectory: workingDirectory,
          environment: environment,
        ).stdout
        as String;

List<int> packagingCommandBytes(String executable, List<String> arguments) =>
    _packagingProcess(executable, arguments, stdoutEncoding: null).stdout
        as List<int>;

String packagingSha256(File file) => packagingCommand('sha256sum', [
  '--',
  file.absolute.path,
]).trim().replaceFirst(RegExp(r'^\\'), '').split(' ').first;

String fileName(FileSystemEntity file) =>
    file.uri.pathSegments.where((segment) => segment.isNotEmpty).last;

Object? sortedJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: sortedJson(value[key])};
  }
  if (value is List) return value.map(sortedJson).toList();
  return value;
}

bool sameJson(Object? first, Object? second) =>
    jsonEncode(sortedJson(first)) == jsonEncode(sortedJson(second));

void writePackagingJson(File file, Object? value) => file.writeAsStringSync(
  '${const JsonEncoder.withIndent('  ').convert(sortedJson(value))}\n',
);
