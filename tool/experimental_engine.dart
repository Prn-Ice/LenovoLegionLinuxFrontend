// Inputs for this isolated engine experiment, never a production SDK fallback.
import 'dart:convert';
import 'dart:io';

import 'package_linux.dart' show fileSha256, runPackagingCommand;

List<String> experimentalEngineArguments() {
  final export = Platform.environment['LLLF_ENGINE_EXPORT'];
  if (export == null) return [];
  return [
    '--local-engine-src-path=$export/engine/src',
    '--local-engine=host_release',
    '--local-engine-host=host_release',
  ];
}

Future<Map<String, Object>?> experimentalEngineInputs() async {
  final export = Platform.environment['LLLF_ENGINE_EXPORT'];
  if (export == null) return null;
  final variant = Platform.environment['LLLF_APP_VARIANT'];
  if (variant != 'A' && variant != 'B') {
    throw StateError('Set LLLF_APP_VARIANT to A or B for the experiment.');
  }
  final manifestFile = File('$export/manifest.json');
  final manifest = jsonDecode(await manifestFile.readAsString()) as Map;
  if (manifest['experimental'] != true ||
      manifest['release_qualification'] != false ||
      manifest['build']['runtime_mode'] != 'release' ||
      manifest['build']['target_cpu'] != 'x64') {
    throw StateError('The export is not the approved release/AOT experiment.');
  }
  for (final key in [
    'runtime',
    'gen_snapshot',
    'frontend_server',
    'platform_dill',
    'icu',
    'source_archive',
  ]) {
    final entry = manifest[key] as Map;
    if (await fileSha256(File('$export/${entry['path']}')) != entry['sha256']) {
      throw StateError('Experimental input hash mismatch: $key');
    }
  }
  return {
    'experimental': true,
    'release_qualification': false,
    'variant': variant!,
    'export_manifest_sha256': await fileSha256(manifestFile),
    'engine': manifest.cast<String, Object>(),
    'local_engine_arguments': experimentalEngineArguments(),
  };
}

Future<void> archiveExperimentalEngine(Directory destination) async {
  final export = Platform.environment['LLLF_ENGINE_EXPORT'];
  if (export == null) return;
  await destination.create();
  final manifest =
      jsonDecode(await File('$export/manifest.json').readAsString()) as Map;
  for (final path in [
    'manifest.json',
    'SHA256SUMS',
    'evidence/provenance',
    manifest['source_archive']['path'] as String,
  ]) {
    await runPackagingCommand('cp', ['-a', '$export/$path', destination.path]);
  }
}
