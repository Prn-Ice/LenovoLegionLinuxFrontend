// Collect notices that Flutter's top-level LICENSE scan does not include.
// Run after building, or use --check to verify an existing bundle without writes.
import 'dart:convert';
import 'dart:io';

const _supplements = <String, List<String>>{
  'yaru': ['assets/LICENSE.CCBYSA', 'assets/fonts/LICENCE.txt'],
  'handy_window': [
    'linux/libhandy/src/COPYING',
    'linux/libhandy/src/AUTHORS',
    'linux/settings/LICENCE',
  ],
};

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final paths = args.where((arg) => arg != '--check').toList();
  if (paths.length != 1) {
    stderr.writeln('Usage: dart tool/bundle_notices.dart [--check] <bundle>');
    exitCode = 64;
    return;
  }
  try {
    final root = File.fromUri(Platform.script).parent.parent;
    final inventory = await bundleNotices(
      root,
      Directory(paths.single),
      check: check,
    );
    stdout.writeln(
      '${check ? 'Checked' : 'Packaged'} notices: '
      '${(inventory['runtime_dependencies'] as Map).length} runtime packages, '
      '${(inventory['fonts'] as List).length} font families, '
      '${(inventory['native_libraries'] as List).length} native libraries.',
    );
  } catch (error) {
    stderr.writeln('Bundle notices: $error');
    exitCode = 1;
  }
}

Future<Map<String, Object>> bundleNotices(
  Directory root,
  Directory bundle, {
  bool check = false,
}) async {
  final assets = Directory('${bundle.path}/data/flutter_assets');
  final compressed = File('${assets.path}/NOTICES.Z');
  final notices = compressed.existsSync()
      ? utf8.decode(gzip.decode(await compressed.readAsBytes()))
      : await File('${assets.path}/NOTICES').readAsString();
  if (notices.trim().isEmpty) throw StateError('Flutter notices are empty');

  final configFile = File('${root.path}/.dart_tool/package_config.json');
  final config = jsonDecode(await configFile.readAsString()) as Map;
  final packages = <String, Directory>{
    for (final package in config['packages'] as List)
      package['name'] as String: Directory.fromUri(
        configFile.absolute.uri.resolve(package['rootUri'] as String),
      ),
  };
  final graph =
      jsonDecode(
            await File(
              '${root.path}/.dart_tool/package_graph.json',
            ).readAsString(),
          )
          as Map;
  final nodes = <String, Map>{
    for (final package in graph['packages'] as List)
      package['name'] as String: package as Map,
  };
  final runtime = <String>{};
  void visit(String name) {
    if (!runtime.add(name)) return;
    for (final dependency in nodes[name]!['dependencies'] as List) {
      visit(dependency as String);
    }
  }

  for (final name in graph['roots'] as List) {
    visit(name as String);
  }
  runtime.removeAll((graph['roots'] as List).cast<String>());
  final names = runtime.toList()..sort();

  final sources = <String, File>{
    'LICENSE': File('${root.path}/LICENSE'),
    'THIRD_PARTY_NOTICES.md': File('${root.path}/THIRD_PARTY_NOTICES.md'),
    'assets/gpu_vendors/README.md': File(
      '${root.path}/assets/gpu_vendors/README.md',
    ),
    for (final entry in _supplements.entries)
      for (final path in entry.value)
        '${entry.key}/$path': File('${packages[entry.key]!.path}/$path'),
    'flutter/MaterialIcons_LICENSE.txt': File(
      '${packages['flutter']!.parent.parent.path}/bin/cache/artifacts/'
      'material_fonts/MaterialIcons_LICENSE.txt',
    ),
  };
  // Read every source before writing so missing notices fail the build.
  final contents = <String, List<int>>{};
  for (final entry in sources.entries) {
    final bytes = await entry.value.readAsBytes();
    if (bytes.isEmpty) throw StateError('Empty notice: ${entry.value.path}');
    contents[entry.key] = bytes;
  }

  final libraries = <String>[];
  await for (final file in Directory(
    '${bundle.path}/lib',
  ).list(recursive: true)) {
    if (file is File && RegExp(r'\.so(?:\.|$)').hasMatch(file.path)) {
      libraries.add(file.path.substring(bundle.path.length + 1));
    }
  }
  libraries.sort();
  final components = <String>{};
  for (final section in notices.split('\n${'-' * 80}\n')) {
    components.addAll(section.split('\n\n').first.split('\n'));
  }
  final inventory = <String, Object>{
    'runtime_dependencies': {
      for (final name in names) name: nodes[name]!['version'],
    },
    // Flutter includes development and engine notices as well as runtime ones.
    'flutter_notice_components': components.toList()..sort(),
    'fonts': jsonDecode(
      await File('${assets.path}/FontManifest.json').readAsString(),
    ),
    'native_libraries': libraries,
    'supplemental_notices': sources.keys.toList()..sort(),
  };
  contents['inventory.json'] = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert(inventory)}\n',
  );
  for (final entry in contents.entries) {
    final target = File(
      '${bundle.path}/share/licenses/legion_frontend/${entry.key}',
    );
    if (check) {
      final actual = await target.readAsBytes();
      if (base64Encode(actual) != base64Encode(entry.value)) {
        throw StateError('Outdated notice or inventory: ${target.path}');
      }
    } else {
      await target.parent.create(recursive: true);
      await target.writeAsBytes(entry.value);
    }
  }
  return inventory;
}
