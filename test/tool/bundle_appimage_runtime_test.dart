// Check runtime dependency failures and source attribution before packaging.
@Tags(['tooling'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/packaging/bundle_appimage_runtime.dart' as runtime;
import '../../tool/packaging/packaging_files.dart';

class OwnedRuntimeBundle extends runtime.RuntimeBundle {
  OwnedRuntimeBundle(super.appdir, super.inputs);

  @override
  String owner(File path) => 'test-package';
}

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('runtime with spaces ');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  test('repeated package attribution stays a package name', () {
    final source = File('${root.path}/source.so')..writeAsStringSync('library');
    final bundle = runtime.RuntimeBundle(
      Directory('${root.path}/app'),
      Directory('${root.path}/inputs'),
    );
    bundle.packages['fixture'] = {
      'version': '1',
      'source': 'fixture',
      'source_version': '1',
    };
    final target = File('${bundle.bundle.path}/lib/test.so');
    bundle.copy(source, target, packageName: 'fixture');
    expect(
      bundle.files['usr/lib/legion_frontend/lib/test.so']!['package'],
      'fixture',
    );
  });

  test('source changed after linking cannot be archived as the original', () {
    final bundle = runtime.RuntimeBundle(
      Directory('${root.path}/app'),
      Directory('${root.path}/inputs'),
    );
    final sources = Directory('${bundle.inputs.path}/sources/example')
      ..createSync(recursive: true);
    final archive = File('${sources.path}/example.tar.gz')
      ..writeAsStringSync('original source');
    bundle.sources['example'] = {
      'version': '1',
      'archives': {fileName(archive): packagingSha256(archive)},
    };
    archive.writeAsStringSync('changed source');
    expect(
      bundle.finish,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Source archives changed'),
        ),
      ),
    );
  });

  test('missing dependency stops packaging', () {
    expect(
      () => runtime.dependencies('libgtk-3.so.0 => not found\n'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('libgtk-3'),
        ),
      ),
    );
  });

  test('dependency paths preserve spaces', () {
    expect(
      runtime
          .dependencies(
            ' libgtk-3.so.0 => /app with spaces/libgtk-3.so.0 (0x1234)\n',
          )
          .map((name, file) => MapEntry(name, file.path)),
      {'libgtk-3.so.0': '/app with spaces/libgtk-3.so.0'},
    );
  });

  test('conflicting libraries cannot silently replace a bundle file', () {
    final source = File('${root.path}/source.so')..writeAsStringSync('new');
    final target = File('${root.path}/target.so')
      ..writeAsStringSync('existing');
    final bundle = OwnedRuntimeBundle(
      Directory('${root.path}/app'),
      Directory('${root.path}/inputs'),
    );
    expect(
      () => bundle.copy(source, target),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Conflicting'),
        ),
      ),
    );
    expect(target.readAsStringSync(), 'existing');
  });

  test('copy retains package and hash for source pairing', () {
    final source = File('${root.path}/source.so')..writeAsStringSync('library');
    final bundle = OwnedRuntimeBundle(
      Directory('${root.path}/app'),
      Directory('${root.path}/inputs'),
    );
    final target = File('${bundle.bundle.path}/lib/test.so');
    bundle.copy(source, target);
    final entry = bundle.files['usr/lib/legion_frontend/lib/test.so']!;
    expect(entry['package'], 'test-package');
    expect(entry['sha256'], packagingSha256(source));
  });

  test('helper and cleanup reject every dynamic ELF mechanism', () {
    for (final cleanup in [false, true]) {
      runtime.validateStaticMetadata(
        'There is no dynamic section.',
        cleanup: cleanup,
      );
      for (final metadata in [
        ' INTERP 0x000040',
        ' (NEEDED) Shared library: [libc.so.6]',
        ' (RPATH) Library rpath: [/app/lib]',
        ' (RUNPATH) Library runpath: [/app/lib]',
      ]) {
        expect(
          () => runtime.validateStaticMetadata(metadata, cleanup: cleanup),
          throwsStateError,
        );
      }
    }
  });

  test('cleanup ELF must remain below the systemd input limit', () {
    final cleanup = File('${root.path}/cleanup.elf')
      ..writeAsBytesSync(List.filled(64 * 1024, 0));
    expect(
      () => runtime.validateStaticElf(cleanup, cleanup: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('below 64 KiB'),
        ),
      ),
    );
  });
}
