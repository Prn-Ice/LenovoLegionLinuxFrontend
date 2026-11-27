@Tags(['tooling'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/packaging/packaging_files.dart';

void main() {
  late Directory temporary;
  late File script;
  late File specification;
  late Directory output;
  late List<Map<String, String>> items;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync(
      'runtime fetch with spaces ',
    );
    addTearDown(() => temporary.deleteSync(recursive: true));
    script = File('${temporary.path}/tool/packaging/fetch_appimage_runtime.sh');
    script.parent.createSync(recursive: true);
    File('tool/packaging/fetch_appimage_runtime.sh').copySync(script.path);
    specification = File(
      '${temporary.path}/packaging/appimage/build-inputs.json',
    )..createSync(recursive: true);
    output = Directory('${temporary.path}/downloaded inputs');
    items = [];
    for (final name in ['runtime-x86_64', 'runtime-source.tar.gz']) {
      final source = File('${temporary.path}/$name')
        ..writeAsStringSync('Pinned input: $name');
      items.add({
        'file': name,
        'url': source.uri.toString(),
        'sha256': packagingSha256(source),
      });
    }
    specification.writeAsStringSync(
      jsonEncode({
        'runtime': items.first,
        'runtime_sources': [items.last],
      }),
    );
  });

  ProcessResult fetch() => Process.runSync('bash', [script.path, output.path]);

  test('fetches pinned inputs and reuses checksum-verified cached files', () {
    expect(fetch().exitCode, 0);
    for (final item in items) {
      expect(
        packagingSha256(File('${output.path}/${item['file']}')),
        item['sha256'],
      );
      File.fromUri(Uri.parse(item['url']!)).deleteSync();
    }
    expect(fetch().exitCode, 0);
    expect(
      jsonDecode(File('${output.path}/build-inputs.json').readAsStringSync()),
      jsonDecode(specification.readAsStringSync()),
    );
  });

  test('replaces corrupt cached files only after checking the download', () {
    expect(fetch().exitCode, 0);
    final cached = File('${output.path}/${items.first['file']}')
      ..writeAsStringSync('corrupt cache');
    expect(fetch().exitCode, 0);
    expect(packagingSha256(cached), items.first['sha256']);
    expect(File('${cached.path}.part').existsSync(), false);
  });

  test('rejects a mismatched download and removes its partial file', () {
    File.fromUri(Uri.parse(items.first['url']!))
        .writeAsStringSync('changed upstream');
    final result = fetch();
    expect(result.exitCode, 1);
    expect(result.stderr, contains('Checksum does not match'));
    expect(File('${output.path}/${items.first['file']}').existsSync(), false);
    expect(
      File('${output.path}/${items.first['file']}.part').existsSync(),
      false,
    );
    expect(File('${output.path}/build-inputs.json').existsSync(), false);
  });

  test('missing source archive specification fails before download', () {
    specification.writeAsStringSync(jsonEncode({'runtime': items.first}));
    expect(fetch().exitCode, isNot(0));
    expect(output.existsSync(), false);
  });
}
