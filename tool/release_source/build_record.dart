/// Paths, permissions, link targets, and checksums in the source manifest.
typedef ReleaseTreeInventory = Map<String, Map<String, String>>;

class ReleasePackageInputs {
  const ReleasePackageInputs({required this.version, required this.files});

  final String version;
  final ReleaseTreeInventory files;

  Map<String, Object> toJson() => {'version': version, 'files': files};
}

/// Source contents recorded before the compiler runs.
class ReleaseInputs {
  const ReleaseInputs({
    required this.commit,
    required this.lockfileSha256,
    required this.packages,
    required this.flutterSdk,
  });

  final String commit;
  final String lockfileSha256;
  final Map<String, ReleasePackageInputs> packages;
  final Map<String, Object>? flutterSdk;

  Map<String, Object> toJson() => {
    'commit': commit,
    'lockfile_sha256': lockfileSha256,
    'packages': {
      for (final entry in packages.entries) entry.key: entry.value.toJson(),
    },
    'flutter_sdk': flutterSdk ?? 'not resolved',
  };
}

/// Pairs the recorded inputs with every file shipped in the built bundle.
class ReleaseBuildRecord {
  const ReleaseBuildRecord({
    required this.inputs,
    required this.binarySha256,
    required this.bundle,
    this.staticHelper = false,
  });

  factory ReleaseBuildRecord.fromJson(Map<String, Object?> json) {
    final configuration = json['build_config'];
    if (configuration is! Map || configuration['portable_control'] != true) {
      throw StateError(
        'The build record must include the privileged control helper.',
      );
    }
    if (json['bundle'] is! Map) {
      throw StateError('The build record must include the whole bundle.');
    }
    final inputs = json['inputs'] as Map;
    final packages = inputs['packages'] as Map;
    final sdk = inputs['flutter_sdk'];
    return ReleaseBuildRecord(
      inputs: ReleaseInputs(
        commit: inputs['commit'] as String,
        lockfileSha256: inputs['lockfile_sha256'] as String,
        packages: {
          for (final entry in packages.entries)
            entry.key as String: ReleasePackageInputs(
              version: (entry.value as Map)['version'] as String,
              files: _readInventory(entry.value['files'] as Map),
            ),
        },
        flutterSdk: switch (sdk) {
          Map value => value.cast<String, Object>(),
          'not resolved' => null,
          _ => throw StateError('Invalid Flutter SDK source metadata.'),
        },
      ),
      binarySha256: json['binary_sha256'] as String,
      bundle: _readInventory(json['bundle'] as Map),
      staticHelper: configuration['static_portable_helper'] == true,
    );
  }

  final ReleaseInputs inputs;
  final String binarySha256;
  final ReleaseTreeInventory bundle;
  final bool staticHelper;

  Map<String, Object> get buildConfiguration => {
    'portable_control': true,
    if (staticHelper) 'static_portable_helper': true,
  };

  Map<String, Object> toJson() => {
    'inputs': inputs.toJson(),
    'binary_sha256': binarySha256,
    'bundle': bundle,
    'build_config': buildConfiguration,
  };
}

ReleaseTreeInventory _readInventory(Map json) => {
  for (final entry in json.entries)
    entry.key as String: (entry.value as Map).cast<String, String>(),
};
