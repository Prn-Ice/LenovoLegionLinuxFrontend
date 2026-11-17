// Shared file and process operations for dependency-free packaging tools.
import 'dart:convert';
import 'dart:io';

String packagingCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  final result = Process.runSync(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: environment == null,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return result.stdout as String;
}

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
