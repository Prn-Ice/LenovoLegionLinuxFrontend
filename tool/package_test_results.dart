import 'dart:convert';
import 'dart:io';

import 'packaging_files.dart';

const passedAppImageChecks =
    'FUSE, extraction, desktop launch, and synthetic helper control verified';
const passedDebianChecks =
    'install, desktop, helper, upgrade, and purge verified';

enum PackageTestFormat {
  native,
  appimage,
  deb;

  static PackageTestFormat parse(String value) => switch (value) {
    'native' => native,
    'appimage' => appimage,
    'deb' => deb,
    _ => throw FormatException('Unknown package test format: $value'),
  };

  String get archiveName => '$name-qualification.tar.gz';
}

/// Writes the source commit, test environment, and file checksums to JSON.
/// The distro test runner calls this after the VM passes and its logs are copied.
void writeDistroTestResults(
  Directory directory, {
  required String commit,
  required bool sourceHasLocalEdits,
  required String cloudImageSha256,
  required String cpuModel,
  required PackageTestFormat format,
}) {
  final source = File('${directory.path}/native-source.tar.gz');
  final testArchive = File('${directory.path}/${format.archiveName}');
  final testResults = {
    'commit': commit,
    'source_worktree_modified': sourceHasLocalEdits,
    'cloud_image_sha256': cloudImageSha256,
    'cpu_model': cpuModel,
    'files': {
      fileName(source): packagingSha256(source),
      fileName(testArchive): packagingSha256(testArchive),
    },
    'scope': 'Hardware control with a synthetic CLI in a disposable distro VM',
    'hardware': 'unverified',
    'desktop_authentication': 'unverified',
    'appimage': format == PackageTestFormat.appimage
        ? passedAppImageChecks
        : 'unverified',
    'deb': format == PackageTestFormat.deb ? passedDebianChecks : 'unverified',
  };
  writePackagingJson(File('${directory.path}/manifest.json'), testResults);
}

/// Adds the NixOS test archive's checksum to an existing test-results file.
/// CI calls this after the NixOS package tests pass; other fields are preserved.
void addNixosTestResults(Directory directory) {
  final resultsFile = File('${directory.path}/manifest.json');
  final testResults = jsonDecode(resultsFile.readAsStringSync()) as Map;
  final testArchive = File(
    '${directory.path}/appimage-nixos-qualification.tar.gz',
  );
  final fileChecksums = testResults['files'] as Map;
  fileChecksums[fileName(testArchive)] = packagingSha256(testArchive);
  final temporary = File('${resultsFile.path}.tmp');
  try {
    writePackagingJson(temporary, testResults);
    temporary.renameSync(resultsFile.path);
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
}
