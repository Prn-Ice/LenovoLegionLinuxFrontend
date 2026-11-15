import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/bundle_notices.dart';

void main() {
  late Directory root;
  late Directory bundle;

  void write(String path, String text) {
    final file = File('${root.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('bundle notices ');
    bundle = Directory('${root.path}/bundle');
    addTearDown(() => root.deleteSync(recursive: true));
    const packagePaths = {
      'app': '../',
      'yaru': '../packages/yaru',
      'handy_window': '../packages/handy_window',
      'flutter': '../sdk/packages/flutter',
      'dev_tool': '../packages/dev_tool',
    };
    write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'packages': [
          for (final entry in packagePaths.entries)
            {'name': entry.key, 'rootUri': entry.value},
        ],
      }),
    );
    write(
      '.dart_tool/package_graph.json',
      jsonEncode({
        'roots': ['app'],
        'packages': [
          for (final name in packagePaths.keys)
            {
              'name': name,
              'version': '1.0.0',
              'dependencies': name == 'app'
                  ? ['yaru', 'handy_window', 'flutter']
                  : [],
              'devDependencies': name == 'app' ? ['dev_tool'] : [],
            },
        ],
      }),
    );
    for (final path in [
      'LICENSE',
      'THIRD_PARTY_NOTICES.md',
      'assets/gpu_vendors/README.md',
      'packages/yaru/assets/LICENSE.CCBYSA',
      'packages/yaru/assets/fonts/LICENCE.txt',
      'packages/handy_window/linux/libhandy/src/COPYING',
      'packages/handy_window/linux/libhandy/src/AUTHORS',
      'packages/handy_window/linux/settings/LICENCE',
      'sdk/bin/cache/artifacts/material_fonts/MaterialIcons_LICENSE.txt',
    ]) {
      write(path, 'Original notice for $path\r\nCopyright ©\r\n');
    }
    write('bundle/data/flutter_assets/FontManifest.json', '[]');
    File('${bundle.path}/data/flutter_assets/NOTICES.Z').writeAsBytesSync(
      gzip.encode(utf8.encode('flutter\n\nOriginal Flutter notice\n')),
    );
    write('bundle/lib/libflutter_linux_gtk.so', 'binary fixture');
  });

  test('preserves full notices and inventories the built bundle', () async {
    final flutterNotice = File('${bundle.path}/data/flutter_assets/NOTICES.Z');
    final original = flutterNotice.readAsBytesSync();
    final inventory = await bundleNotices(root, bundle);
    final copied = File(
      '${bundle.path}/share/licenses/legion_frontend/'
      'yaru/assets/fonts/LICENCE.txt',
    );
    expect(
      copied.readAsBytesSync(),
      File(
        '${root.path}/packages/yaru/assets/fonts/LICENCE.txt',
      ).readAsBytesSync(),
    );
    expect(flutterNotice.readAsBytesSync(), original);
    expect(inventory['runtime_dependencies'], {
      'flutter': '1.0.0',
      'handy_window': '1.0.0',
      'yaru': '1.0.0',
    });
    await bundleNotices(root, bundle, check: true);

    write('bundle/lib/libnew_dependency.so', 'new binary');
    await expectLater(
      bundleNotices(root, bundle, check: true),
      throwsStateError,
    );
  });

  test('check rejects altered notices without repairing them', () async {
    await bundleNotices(root, bundle);
    const path = 'bundle/share/licenses/legion_frontend/LICENSE';
    write(path, 'truncated');
    await expectLater(
      bundleNotices(root, bundle, check: true),
      throwsStateError,
    );
    expect(File('${root.path}/$path').readAsStringSync(), 'truncated');
  });

  test('uses the build SDK when its Flutter package has a store alias', () async {
    final flutterPackage = Directory('${root.path}/sdk/packages/flutter')
      ..createSync(recursive: true);
    final alias = Link('${root.path}/store-flutter')
      ..createSync(flutterPackage.path);
    final config = File('${root.path}/.dart_tool/package_config.json');
    final data = jsonDecode(config.readAsStringSync()) as Map;
    for (final package in data['packages'] as List) {
      if (package['name'] == 'flutter') {
        package['rootUri'] = alias.uri.toString();
      }
    }
    config.writeAsStringSync(jsonEncode(data));

    await bundleNotices(
      root,
      bundle,
      flutterSdk: Directory('${root.path}/sdk'),
    );
    final copied = File(
      '${bundle.path}/share/licenses/legion_frontend/flutter/MaterialIcons_LICENSE.txt',
    );
    expect(
      copied.readAsBytesSync(),
      File(
        '${root.path}/sdk/bin/cache/artifacts/material_fonts/MaterialIcons_LICENSE.txt',
      ).readAsBytesSync(),
    );
    await bundleNotices(
      root,
      bundle,
      check: true,
      flutterSdk: Directory('${root.path}/sdk'),
    );
  });

  test('missing nested source notice fails before packaging', () async {
    File(
      '${root.path}/packages/handy_window/linux/libhandy/src/COPYING',
    ).deleteSync();
    await expectLater(
      bundleNotices(root, bundle),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory('${bundle.path}/share/licenses').existsSync(), isFalse);
  });
}
