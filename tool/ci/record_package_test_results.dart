import 'dart:io';

import 'package_test_results.dart';

const _usage =
    'Usage: dart tool/ci/record_package_test_results.dart '
    'distro DIRECTORY COMMIT MODIFIED IMAGE_SHA256 CPU native|appimage|deb\n'
    '       dart tool/ci/record_package_test_results.dart nixos DIRECTORY';

void main(List<String> arguments) {
  try {
    switch (arguments) {
      case [
        'distro',
        final directory,
        final commit,
        final modified,
        final imageSha256,
        final cpuModel,
        final format,
      ]:
        writeDistroTestResults(
          Directory(directory),
          commit: commit,
          sourceHasLocalEdits: modified.isNotEmpty,
          cloudImageSha256: imageSha256,
          cpuModel: cpuModel,
          format: PackageTestFormat.parse(format),
        );
      case ['nixos', final directory]:
        addNixosTestResults(Directory(directory));
      default:
        throw const FormatException(_usage);
    }
  } catch (error) {
    stderr.writeln('Could not record package test results: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}
