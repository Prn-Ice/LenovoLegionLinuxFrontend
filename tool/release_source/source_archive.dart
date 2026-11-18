import 'dart:convert';
import 'dart:io';

import 'build_record.dart';
import 'rebuild_instructions.dart';
import 'source_files.dart';
import 'source_inputs.dart';

/// Archives the source inputs only while they still match the built bundle.
Future<Map<String, Object>> packageReleaseSource(
  Directory root,
  Directory bundle,
  File output,
  ReleaseBuildRecord record, {
  Directory? additionalSources,
}) async {
  await _verifyBuildPairing(root, bundle, record);
  final sources = await resolveReleaseSources(root);
  final staging = await Directory.systemTemp.createTemp('legion-release-');
  try {
    final applicationSource = Directory('${staging.path}/source');
    await extractApplicationSource(
      root,
      applicationSource,
      record.inputs.commit,
    );
    await _stageAdditionalSources(staging, additionalSources);
    await _stageDependencies(staging, sources.packages, record.inputs.packages);
    await _writeRebuildFiles(staging, sources.packages.keys, record);
    final manifest = await _writeSourceManifest(
      staging,
      applicationSource,
      bundle,
      record,
      additionalSources,
    );
    await createSourceArchive(staging, output);
    return manifest;
  } finally {
    // The archive retains original modes; make this owned copy removable.
    await Process.run('chmod', ['-R', 'u+w', '--', staging.path]);
    await staging.delete(recursive: true);
  }
}

Future<void> _verifyBuildPairing(
  Directory root,
  Directory bundle,
  ReleaseBuildRecord record,
) async {
  if (jsonEncode(await captureReleaseInputs(root)) !=
      jsonEncode(record.inputs)) {
    throw StateError('Sources changed during the build; build again.');
  }
  if (await releaseFileSha256(File('${bundle.path}/lib/libapp.so')) !=
      record.binarySha256) {
    throw StateError('The built libapp.so changed; build again.');
  }
  if (jsonEncode(await inventoryReleaseTree(bundle)) !=
      jsonEncode(record.bundle)) {
    throw StateError('The built bundle changed; build again.');
  }
}

Future<void> _stageAdditionalSources(
  Directory staging,
  Directory? additionalSources,
) async {
  if (additionalSources == null) return;
  final copied = Directory('${staging.path}/release-inputs');
  await copyPackageSources(additionalSources, copied);
  if (jsonEncode(await inventoryReleaseTree(copied)) !=
      jsonEncode(await inventoryReleaseTree(additionalSources))) {
    throw StateError('Release inputs changed while copying; build again.');
  }
}

Future<void> _stageDependencies(
  Directory staging,
  Map<String, PackageSource> sources,
  Map<String, ReleasePackageInputs> recordedInputs,
) async {
  for (final entry in sources.entries) {
    final copied = Directory('${staging.path}/dependencies/${entry.key}');
    await copyPackageSources(entry.value.root, copied);
    final expected = recordedInputs[entry.key]!.files;
    if (jsonEncode(await inventoryReleaseTree(copied)) !=
        jsonEncode(expected)) {
      throw StateError('${entry.key} changed while copying; build again.');
    }
  }
}

Future<void> _writeRebuildFiles(
  Directory staging,
  Iterable<String> packageNames,
  ReleaseBuildRecord record,
) async {
  // These paths are relative to source/pubspec_overrides.yaml after copying.
  await _writeJson(File('${staging.path}/dependency-overrides.yaml'), {
    'dependency_overrides': {
      for (final name in packageNames) name: {'path': '../dependencies/$name'},
    },
  });
  await File('${staging.path}/REBUILD.md').writeAsString(
    rebuildInstructions(staticPortableHelper: record.staticPortableHelper),
  );
}

Future<Map<String, Object>> _writeSourceManifest(
  Directory staging,
  Directory applicationSource,
  Directory bundle,
  ReleaseBuildRecord record,
  Directory? additionalSources,
) async {
  final manifest = <String, Object>{
    'format': 4,
    'inputs': record.inputs.toJson(),
    'build_config': record.buildConfiguration,
    'binary_sha256': record.binarySha256,
    'bundle': await inventoryReleaseTree(bundle),
    'application_source': await inventoryReleaseTree(applicationSource),
    if (additionalSources != null)
      'release_inputs': await inventoryReleaseTree(additionalSources),
  };
  await _writeJson(File('${staging.path}/SOURCE-MANIFEST.json'), manifest);
  return manifest;
}

Future<void> _writeJson(File output, Map<String, Object> value) => output
    .writeAsString('${const JsonEncoder.withIndent('  ').convert(value)}\n');
