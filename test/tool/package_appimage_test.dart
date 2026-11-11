import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/package_appimage.dart';

void main() {
  late Directory temporary;
  late Directory bundle;
  late Directory inputs;
  final root = Directory.current;

  void write(String path, String contents) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'AppImage packaging with spaces ',
    );
    addTearDown(() => temporary.delete(recursive: true));
    bundle = Directory('${temporary.path}/bundle')..createSync();
    inputs = Directory('${temporary.path}/inputs')..createSync();
    write(
      '${bundle.path}/legion_frontend',
      '#!/bin/sh\nprintf \'%s\\n\' "\$@" "\$LD_LIBRARY_PATH"\n',
    );
    await Process.run('chmod', ['755', '${bundle.path}/legion_frontend']);
    write('${bundle.path}/libexec/legion-portable-control', 'helper');
    write(
      '${bundle.path}/libexec/legion-telemetry-service',
      'installed telemetry',
    );
    write(
      '${bundle.path}/lib/systemd/system/legion-control.service',
      'installed service',
    );
    write(
      '${bundle.path}/share/polkit-1/actions/legion.policy',
      'installed policy',
    );
    write(
      '${bundle.path}/data/flutter_assets/NOTICES.Z',
      'existing Flutter notices',
    );
    write(
      '${bundle.path}/share/licenses/legion_frontend/LICENSE',
      'project license',
    );
    final specification =
        jsonDecode(
              File(
                '${root.path}/packaging/appimage/build-inputs.json',
              ).readAsStringSync(),
            )
            as Map;
    for (final item in specification['runtime_sources'] as List) {
      final source = Directory('${temporary.path}/source-${item['name']}')
        ..createSync();
      write('${source.path}/${item['license']}', '${item['name']} license');
      for (final path in item['additional_licenses'] as List? ?? []) {
        write('${source.path}/$path', '${item['name']} supplementary license');
      }
      final result = await Process.run('tar', [
        '-czf',
        '${inputs.path}/${item['file']}',
        '-C',
        source.path,
        (item['license'] as String).split('/').first,
      ]);
      expect(result.exitCode, 0);
    }
  });

  test(
    'stages portable files, metadata, and notices without installed service files',
    () async {
      final appdir = Directory('${temporary.path}/Legion.AppDir');
      await stageAppDir(root, bundle, appdir, runtimeInputs: inputs);
      final base = '${appdir.path}/usr/lib/legion_frontend';
      expect(
        File('$base/libexec/legion-portable-control').readAsStringSync(),
        'helper',
      );
      expect(
        File('$base/libexec/legion-telemetry-service').existsSync(),
        isFalse,
      );
      expect(Directory('$base/lib/systemd').existsSync(), isFalse);
      expect(Directory('$base/share/polkit-1').existsSync(), isFalse);
      expect(File('$base/data/flutter_assets/NOTICES.Z').existsSync(), isTrue);
      expect(
        File('$base/share/licenses/legion_frontend/LICENSE').existsSync(),
        isTrue,
      );
      expect(
        File(
          '${appdir.path}/usr/share/metainfo/$appId.metainfo.xml',
        ).existsSync(),
        isTrue,
      );
      expect(
        File('${appdir.path}/$appId.svg').readAsStringSync(),
        File('${root.path}/assets/branding/legion_mark.svg').readAsStringSync(),
      );
      expect(
        File(
          '${appdir.path}/usr/share/licenses/appimage-runtime/libfuse.txt',
        ).readAsStringSync(),
        contains('libfuse license'),
      );
    },
  );

  test('AppRun preserves arguments and paths containing spaces', () async {
    final appdir = Directory('${temporary.path}/Legion.AppDir');
    await stageAppDir(root, bundle, appdir, runtimeInputs: inputs);
    final result = await Process.run(
      '${appdir.path}/AppRun',
      ['argument with spaces', r'$literal'],
      environment: {'LD_LIBRARY_PATH': '/original/lib'},
    );
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect((result.stdout as String).split('\n'), [
      'argument with spaces',
      r'$literal',
      '${appdir.path}/usr/lib/legion_frontend/lib:/original/lib',
      '',
    ]);
  });

  test('rejects a bundle without the portable helper', () async {
    File('${bundle.path}/libexec/legion-portable-control').deleteSync();
    await expectLater(
      stageAppDir(
        root,
        bundle,
        Directory('${temporary.path}/Legion.AppDir'),
        runtimeInputs: inputs,
      ),
      throwsStateError,
    );
  });

  test('rejects a corrupted runtime before packaging', () async {
    write('${inputs.path}/runtime-x86_64', 'replacement');
    await expectLater(verifyRuntimeInputs(root, inputs), throwsStateError);
  });
}
