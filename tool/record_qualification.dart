import 'dart:io';

import 'qualification_manifest.dart';

const _usage =
    'Usage: dart tool/record_qualification.dart '
    'distro DIRECTORY COMMIT MODIFIED IMAGE_SHA256 CPU native|appimage|deb\n'
    '       dart tool/record_qualification.dart nixos DIRECTORY';

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
        writeDistroQualification(
          Directory(directory),
          commit: commit,
          sourceWorktreeModified: modified.isNotEmpty,
          cloudImageSha256: imageSha256,
          cpuModel: cpuModel,
          format: QualificationFormat.parse(format),
        );
      case ['nixos', final directory]:
        addNixosQualification(Directory(directory));
      default:
        throw const FormatException(_usage);
    }
  } catch (error) {
    stderr.writeln('Qualification manifest: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}
