// Read the small, public part of a Nix Flutter derivation graph.
import 'dart:convert';
import 'dart:io';

Future<Map<String, Object>> nixFlutterProvenance(Directory sdk) async {
  final sdkPath = sdk.resolveSymbolicLinksSync();
  if (!sdkPath.startsWith('/nix/store/')) {
    return {
      'status': 'unavailable',
      'reason': 'The Flutter SDK is not installed from the Nix store.',
    };
  }
  try {
    final drv = (await _command('nix-store', [
      '--query',
      '--deriver',
      sdkPath,
    ])).trim();
    if (!drv.startsWith('/nix/store/') || !drv.endsWith('.drv')) {
      return {
        'status': 'unavailable',
        'reason': 'The SDK derivation is unavailable.',
      };
    }
    final derivations = <String, Map<String, dynamic>>{};
    final pending = <String>[drv];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (derivations.containsKey(current)) continue;
      final found = _derivations(
        jsonDecode(await _command('nix', ['derivation', 'show', current])),
      );
      derivations.addAll(found);
      for (final value in found.values) {
        final drvs = (value['inputs'] as Map?)?['drvs'];
        if (drvs is Map) {
          for (final key in drvs.keys) {
            final name = key.toString();
            pending.add(
              name.startsWith('/nix/store/') ? name : '/nix/store/$name',
            );
          }
        }
      }
    }
    final provenance = parseNixFlutterProvenance(
      derivations,
      sdkDerivation: drv,
    );
    if (provenance['status'] == 'recorded') {
      final unwrapped = derivations.entries
          .firstWhere(
            (entry) =>
                entry.key.contains('flutter-') &&
                entry.key.contains('unwrapped') &&
                (entry.value['structuredAttrs'] as Map?)?['patches'] is List,
          )
          .value;
      final patches = (unwrapped['structuredAttrs']['patches'] as List)
          .whereType<String>()
          .toList();
      final records = provenance['patches'] as List;
      for (var i = 0; i < records.length && i < patches.length; i++) {
        (records[i] as Map)['content_sha256'] = await _sha256Path(patches[i]);
      }
    }
    return provenance;
  } catch (_) {
    return {
      'status': 'unavailable',
      'reason':
          'Nix derivation metadata is unavailable (it may have been garbage-collected).',
    };
  }
}

/// Parses `nix derivation show` output without requiring Nix in tests.
Map<String, Object> parseNixFlutterProvenance(
  Map<String, Map<String, dynamic>> derivations, {
  required String sdkDerivation,
}) {
  Map<String, dynamic>? unwrapped;
  String? unwrappedId;
  Map<String, dynamic>? fetcher;
  String? fetcherId;
  for (final entry in derivations.entries) {
    final attrs = entry.value['structuredAttrs'];
    if (attrs is! Map) continue;
    if (attrs['owner'] == 'flutter' &&
        attrs['repo'] == 'flutter' &&
        attrs['urls'] is List) {
      fetcher = entry.value;
      fetcherId = _storeName(entry.key);
    }
    final name = entry.key.toString();
    if (attrs['src'] is String &&
        attrs['patches'] is List &&
        (name.contains('flutter-') && name.contains('unwrapped'))) {
      unwrapped = entry.value;
      unwrappedId = _storeName(entry.key);
    }
  }
  if (unwrapped == null || fetcher == null) {
    return {
      'status': 'unavailable',
      'reason': 'Flutter source derivations were not found.',
    };
  }
  final attrs = fetcher['structuredAttrs'] as Map;
  final urls = (attrs['urls'] as List).whereType<String>().toList();
  final outputHash = attrs['outputHash'];
  final output = (fetcher['outputs'] as Map?)?['out'];
  final outputMap = output is Map ? output : const <String, dynamic>{};
  final source = <String, Object>{
    'url': urls.isEmpty ? 'unknown' : urls.first,
    'ref': attrs['rev'] is String ? attrs['rev'] as String : 'unknown',
    'hash': outputHash is String
        ? outputHash
        : (outputMap['hash'] is String
              ? outputMap['hash'] as String
              : 'unknown'),
    'hash_algorithm': 'sha256',
    'hash_encoding': 'nix-store-base64',
    'hash_mode': attrs['outputHashMode'] ?? 'unknown',
  };
  final patches = <Map<String, Object>>[];
  for (final patch in (unwrapped['structuredAttrs']['patches'] as List)) {
    if (patch is String) patches.add({'store_name': _storeName(patch)});
  }
  String? prepared;
  for (final entry in derivations.entries) {
    final drvs = (entry.value['inputs'] as Map?)?['drvs'];
    if (drvs is Map &&
        drvs.keys.any((key) => _storeName(key.toString()) == fetcherId)) {
      prepared = _storeName(entry.key);
      break;
    }
  }
  return {
    'status': 'recorded',
    'distributor': 'Nix',
    'source': source,
    'derivations': {
      'sdk': _storeName(sdkDerivation),
      'unwrapped': unwrappedId!,
      'source_fetcher': fetcherId!,
      'prepared_source': prepared ?? 'unknown',
    },
    'patches': patches,
  };
}

Map<String, Map<String, dynamic>> _derivations(dynamic decoded) {
  if (decoded is! Map || decoded['derivations'] is! Map) return {};
  final result = <String, Map<String, dynamic>>{};
  for (final entry in (decoded['derivations'] as Map).entries) {
    if (entry.value is Map) {
      final key = entry.key.toString();
      result[key.startsWith('/nix/store/') ? key : '/nix/store/$key'] =
          Map<String, dynamic>.from(entry.value as Map);
    }
  }
  return result;
}

String _storeName(String path) => path.split('/').last;

Future<String> _command(String executable, List<String> args) async {
  final result = await Process.run(executable, args);
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
  return result.stdout.toString();
}

Future<String> _sha256Path(String path) async {
  try {
    final result = await Process.run('sha256sum', ['--binary', '--', path]);
    if (result.exitCode == 0) return result.stdout.toString().substring(0, 64);
  } catch (_) {}
  return 'unknown';
}
