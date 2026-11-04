// Identify the source and patches used by the installed Nix Flutter framework.
import 'dart:convert';
import 'dart:io';

typedef NixCommand =
    Future<String> Function(String executable, List<String> args);

enum NixProvenanceStatus { recorded, unavailable, notApplicable }

enum NixSourceHashMode { nar, flat }

Future<Map<String, Object>> nixFlutterProvenance(
  Directory sdk, {
  NixCommand? command,
}) async {
  final run = command ?? _command;
  try {
    final sdkPath = (await run('readlink', ['-f', '--', sdk.path])).trim();
    final sdkStore = _storeRoot(sdkPath);
    if (sdkStore == null) {
      return {
        'status': NixProvenanceStatus.notApplicable.name,
        'reason': 'The Flutter SDK is not installed from the Nix store.',
      };
    }
    // SDK wrappers can link to other packages. Follow a framework source file
    // to identify the framework we compiled, rather than scanning the toolchain.
    final frameworkFile = (await run('readlink', [
      '-f',
      '--',
      '$sdkPath/packages/flutter/lib/src/foundation/constants.dart',
    ])).trim();
    final frameworkStore = _storeRoot(frameworkFile);
    if (frameworkStore == null) throw const FormatException();

    Future<String> deriver(String storePath) async {
      final path = (await run('nix-store', [
        '--query',
        '--deriver',
        storePath,
      ])).trim();
      return _derivationPath(path);
    }

    Future<Map> readDerivation(String path) async {
      final decoded =
          jsonDecode(await run('nix', ['derivation', 'show', path])) as Map;
      // Nix 2.x used absolute keys at the top level; newer Nix wraps store names.
      final records = (decoded['derivations'] ?? decoded) as Map;
      return (records[path] ?? records[_storeName(path)]) as Map;
    }

    final sdkDerivation = await deriver(sdkStore);
    final frameworkDerivation = await deriver(frameworkStore);
    final framework = _attributes(await readDerivation(frameworkDerivation));
    final sourcePath = framework['src'];
    if (sourcePath is! String || _storeRoot(sourcePath) != sourcePath) {
      throw const FormatException();
    }
    var current = await deriver(sourcePath);
    final chain = <String>[];
    Map<String, Object>? source;
    while (chain.length < 8 && !chain.contains(current)) {
      chain.add(current);
      final derivation = await readDerivation(current);
      final attrs = _attributes(derivation);
      if (attrs['urls'] != null) {
        source = _sourceRecord(attrs, derivation);
        break;
      }
      // Nixpkgs prepares Flutter's fetched tree by adding engine stamps. Follow
      // its source input only. Multiple source inputs require explicit support.
      final inputs =
          ((derivation['inputs'] as Map?)?['drvs'] ?? derivation['inputDrvs'])
              as Map?;
      final sourceInputs = inputs?.keys
          .whereType<String>()
          .where((name) => name.endsWith('-source.drv'))
          .map(_derivationPath)
          .toList();
      if (sourceInputs == null || sourceInputs.length != 1) {
        throw const FormatException();
      }
      current = sourceInputs.single;
    }
    if (source == null) throw const FormatException();

    final patchValue = framework['patches'];
    final patches = switch (patchValue) {
      final List values => values.cast<String>(),
      final String value =>
        value.split(RegExp(r'\s+')).where((v) => v.isNotEmpty).toList(),
      _ => throw const FormatException(),
    };
    final patchRecords = <Map<String, String>>[];
    for (final path in patches) {
      if (_storeRoot(path) != path) throw const FormatException();
      final checksum = await run('sha256sum', [
        '--binary',
        '--zero',
        '--',
        path,
      ]);
      if (!RegExp(r'^[0-9a-f]{64} ').hasMatch(checksum)) {
        throw const FormatException();
      }
      patchRecords.add({
        'store_name': _storeName(path),
        'content_sha256': checksum.substring(0, 64),
      });
    }
    return {
      'status': NixProvenanceStatus.recorded.name,
      'distributor': 'Nix',
      'source': source,
      'derivations': {
        'sdk': _storeName(sdkDerivation),
        'framework': _storeName(frameworkDerivation),
        'source_chain': chain.map(_storeName).toList(),
      },
      'patches': patchRecords,
    };
  } catch (_) {
    // Error output and derivation environments can contain private paths.
    return {
      'status': NixProvenanceStatus.unavailable.name,
      'reason':
          'Nix source metadata or patches are missing or use an unsupported layout.',
    };
  }
}

Map _attributes(Map derivation) {
  if (derivation['structuredAttrs'] case final Map attrs) return attrs;
  final env = derivation['env'] as Map;
  if (env['__json'] case final String encoded) {
    return jsonDecode(encoded) as Map;
  }
  return env;
}

Map<String, Object> _sourceRecord(Map attrs, Map derivation) {
  final urls = switch (attrs['urls']) {
    final List values => values.cast<String>(),
    final String value => value.split(RegExp(r'\s+')),
    _ => throw const FormatException(),
  };
  final ref = attrs['rev'];
  if (ref is! String || !RegExp(r'^[a-zA-Z0-9._/-]+$').hasMatch(ref)) {
    throw const FormatException();
  }
  // Only publish the public upstream Flutter archive URL. Never copy arbitrary
  // fetcher URLs, which can carry credentials or refer to local files.
  final url = 'https://github.com/flutter/flutter/archive/$ref.tar.gz';
  if (!urls.contains(url)) throw const FormatException();
  final output = (derivation['outputs'] as Map?)?['out'] as Map?;
  final hash = attrs['outputHash'] ?? output?['hash'];
  if (hash is! String ||
      !hash.startsWith('sha256-') ||
      base64Decode(hash.substring(7)).length != 32) {
    throw const FormatException();
  }
  final mode = switch (attrs['outputHashMode'] ?? output?['method']) {
    'recursive' || 'nar' => NixSourceHashMode.nar,
    'flat' => NixSourceHashMode.flat,
    _ => throw const FormatException(),
  };
  return {
    'url': url,
    'ref': ref,
    'hash': hash,
    'hash_format': 'sri',
    'hash_mode': mode.name,
  };
}

String? _storeRoot(String path) =>
    RegExp(r'^/nix/store/[a-z0-9]{32}-[^/\s]+(?=/|$)').stringMatch(path);

String _derivationPath(String path) {
  final absolute = path.startsWith('/nix/store/') ? path : '/nix/store/$path';
  if (_storeRoot(absolute) != absolute || !absolute.endsWith('.drv')) {
    throw const FormatException();
  }
  return absolute;
}

String _storeName(String path) => path.split('/').last;

Future<String> _command(String executable, List<String> args) async {
  final result = await Process.run(executable, args);
  if (result.exitCode != 0) throw StateError('Provenance command failed.');
  return result.stdout as String;
}
