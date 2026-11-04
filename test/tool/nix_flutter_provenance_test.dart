import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/nix_flutter_provenance.dart';

void main() {
  for (final legacy in [false, true]) {
    test(
      'follows the framework source and patch chain (legacy: $legacy)',
      () async {
        final fixture = _NixFixture(legacy: legacy);
        final result = await fixture.capture();
        expect(result['status'], 'recorded');
        expect(result['source'], {
          'url': _NixFixture.url,
          'ref': 'refs/tags/3.47.9',
          'hash': _NixFixture.hash,
          'hash_format': 'sri',
          'hash_mode': 'nar',
        });
        expect((result['derivations'] as Map)['source_chain'], [
          fixture.preparedDrv.split('/').last,
          fixture.fetchDrv.split('/').last,
        ]);
        expect(result['patches'], [
          {
            'store_name': fixture.patch.split('/').last,
            'content_sha256': 'c' * 64,
          },
        ]);
        // The fixture includes a private environment and unrelated toolchain input.
        // Its runner rejects attempts to read that unrelated input.
        expect(jsonEncode(result), isNot(contains('PRIVATE')));
        expect(jsonEncode(result), isNot(contains('/nix/store/')));
        expect(jsonEncode(result), isNot(contains('/home/')));
      },
    );
  }

  test('reports a non-Nix SDK without invoking Nix', () async {
    final result = await nixFlutterProvenance(
      Directory('/home/PRIVATE/flutter'),
      command: (executable, args) async {
        expect(executable, 'readlink');
        return '/home/PRIVATE/flutter';
      },
    );
    expect(result['status'], 'notApplicable');
    expect(jsonEncode(result), isNot(contains('PRIVATE')));
  });

  test(
    'does not guess when the source preparation has multiple inputs',
    () async {
      final fixture = _NixFixture();
      fixture.inputDrvs[fixture.preparedDrv]![fixture.otherSource] = {};
      expect((await fixture.capture())['status'], 'unavailable');
    },
  );

  test(
    'missing derivations and patch files do not claim recorded provenance',
    () async {
      final fixture = _NixFixture();
      fixture.missingDeriver = true;
      expect((await fixture.capture())['status'], 'unavailable');
      fixture.missingDeriver = false;
      fixture.missingPatch = true;
      final result = await fixture.capture();
      expect(result['status'], 'unavailable');
      expect(jsonEncode(result), isNot(contains('PRIVATE')));
    },
  );

  test('rejects credential-bearing URLs and incomplete hash metadata', () async {
    final fixture = _NixFixture();
    fixture.attrs[fixture.fetchDrv]!['urls'] = [
      'https://PRIVATE@github.com/flutter/flutter/archive/refs/tags/3.47.9.tar.gz',
    ];
    final result = await fixture.capture();
    expect(result['status'], 'unavailable');
    expect(jsonEncode(result), isNot(contains('PRIVATE')));
    fixture.attrs[fixture.fetchDrv]!['urls'] = [_NixFixture.url];
    fixture.attrs[fixture.fetchDrv]!.remove('outputHashMode');
    expect((await fixture.capture())['status'], 'unavailable');
  });
}

class _NixFixture {
  _NixFixture({this.legacy = false}) {
    attrs[frameworkDrv] = {
      'src': prepared,
      'patches': [patch],
    };
    attrs[preparedDrv] = {'buildCommand': 'PRIVATE build environment'};
    attrs[fetchDrv] = {
      'rev': 'refs/tags/3.47.9',
      'urls': [url],
      'outputHash': hash,
      'outputHashMode': 'recursive',
    };
    inputDrvs[preparedDrv] = {fetchDrv: {}, unrelated: {}};
  }

  static const url =
      'https://github.com/flutter/flutter/archive/refs/tags/3.47.9.tar.gz';
  static const hash = 'sha256-JBauGMdb1lmply2yAekkeonIX7+duVFixiHEREg+EG8=';
  static String store(String name) => '/nix/store/${'a' * 32}-$name';
  final sdk = store('flutter-sdk');
  final sdkDrv = store('flutter-sdk.drv');
  final framework = store('flutter-unwrapped');
  final frameworkDrv = store('flutter-unwrapped.drv');
  final prepared = store('prepared-source');
  final preparedDrv = store('prepared-source.drv');
  final fetchDrv = store('source.drv');
  final otherSource = store('other-source.drv');
  final unrelated = store('compiler.drv');
  final patch = store('flutter.patch');
  final bool legacy;
  bool missingDeriver = false;
  bool missingPatch = false;
  final attrs = <String, Map<String, Object>>{};
  final inputDrvs = <String, Map<String, Object>>{};

  Future<Map<String, Object>> capture() =>
      nixFlutterProvenance(Directory(sdk), command: run);

  Future<String> run(String executable, List<String> args) async {
    if (executable == 'readlink') {
      return args.last == sdk
          ? sdk
          : '$framework/packages/flutter/lib/src/foundation/constants.dart';
    }
    if (executable == 'nix-store') {
      if (missingDeriver) return 'unknown-deriver';
      return {
        sdk: sdkDrv,
        framework: frameworkDrv,
        prepared: preparedDrv,
      }[args.last]!;
    }
    if (executable == 'nix') {
      final path = args.last;
      if (!attrs.containsKey(path)) {
        throw StateError('Unexpected derivation: $path');
      }
      final inputs = inputDrvs[path] ?? {};
      if (legacy) {
        return jsonEncode({
          path: {
            'env': {
              '__json': jsonEncode(attrs[path]),
              'PRIVATE_TOKEN': 'PRIVATE',
            },
            'inputDrvs': inputs,
          },
        });
      }
      return jsonEncode({
        'derivations': {
          path.split('/').last: {
            'structuredAttrs': attrs[path],
            'env': {'PRIVATE_TOKEN': 'PRIVATE'},
            'inputs': {
              'drvs': {
                for (final entry in inputs.entries)
                  entry.key.split('/').last: entry.value,
              },
            },
          },
        },
      });
    }
    if (executable == 'sha256sum' && args.last == patch) {
      if (missingPatch) throw StateError('Missing /home/PRIVATE/patch');
      return '${'c' * 64} *$patch\u0000';
    }
    throw StateError('Unexpected command $executable $args');
  }
}
