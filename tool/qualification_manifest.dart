import 'dart:convert';
import 'dart:io';

import 'packaging_files.dart';

const qualifiedAppImage =
    'FUSE, extraction, desktop launch, and synthetic helper control verified';
const qualifiedDeb = 'install, desktop, helper, upgrade, and purge verified';

enum QualificationFormat {
  native,
  appimage,
  deb;

  static QualificationFormat parse(String value) => switch (value) {
    'native' => native,
    'appimage' => appimage,
    'deb' => deb,
    _ => throw FormatException('Unknown qualification format: $value'),
  };

  String get archiveName => '$name-qualification.tar.gz';
}

/// Records the source and evidence copied from a successful disposable VM run.
void writeDistroQualification(
  Directory directory, {
  required String commit,
  required bool sourceWorktreeModified,
  required String cloudImageSha256,
  required String cpuModel,
  required QualificationFormat format,
}) {
  final source = File('${directory.path}/native-source.tar.gz');
  final evidence = File('${directory.path}/${format.archiveName}');
  final manifest = {
    'commit': commit,
    'source_worktree_modified': sourceWorktreeModified,
    'cloud_image_sha256': cloudImageSha256,
    'cpu_model': cpuModel,
    'files': {
      fileName(source): packagingSha256(source),
      fileName(evidence): packagingSha256(evidence),
    },
    'scope': 'Portable control with a synthetic CLI in a disposable distro VM',
    'hardware': 'unverified',
    'desktop_authentication': 'unverified',
    'appimage': format == QualificationFormat.appimage
        ? qualifiedAppImage
        : 'unverified',
    'deb': format == QualificationFormat.deb ? qualifiedDeb : 'unverified',
  };
  writePackagingJson(File('${directory.path}/manifest.json'), manifest);
}

/// Adds the NixOS archive after its acceptance command succeeds.
void addNixosQualification(Directory directory) {
  final manifestFile = File('${directory.path}/manifest.json');
  final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
  final evidence = File(
    '${directory.path}/appimage-nixos-qualification.tar.gz',
  );
  final files = manifest['files'] as Map;
  files[fileName(evidence)] = packagingSha256(evidence);
  final temporary = File('${manifestFile.path}.tmp');
  try {
    writePackagingJson(temporary, manifest);
    temporary.renameSync(manifestFile.path);
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
}
