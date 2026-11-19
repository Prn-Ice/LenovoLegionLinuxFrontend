import 'dart:convert';
import 'dart:io';

Future<ProcessResult> run(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: environment == null,
  );
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed:\n${result.stderr}',
    );
  }
  return result;
}

String option(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    throw FormatException('missing $name');
  }
  return args[index + 1];
}

Future<void> main(List<String> args) async {
  try {
    final sdk = Directory(option(args, '--sdk')).resolveSymbolicLinksSync();
    final root = Directory(option(args, '--root')).resolveSymbolicLinksSync();
    final source = File(option(args, '--source')).resolveSymbolicLinksSync();
    final output = Directory(option(args, '--output')).absolute;
    final objcopy = option(args, '--objcopy');
    final linker = option(args, '--linker');
    final patchelf = option(args, '--patchelf');
    final pkgConfig = option(args, '--pkg-config');
    final ldd = option(args, '--ldd');
    output.createSync(recursive: true);
    final dart = '$sdk/bin/dart';
    final snapshot = File('${output.path}/helper.aot');
    await run(dart, [
      'compile',
      'aot-snapshot',
      '--packages=$root/.dart_tool/package_config.json',
      '-o',
      snapshot.path,
      source,
    ], workingDirectory: root);
    final runtimePath = '${output.path}/dartaotruntime';
    if (File(runtimePath).existsSync()) {
      await run('chmod', ['u+w', runtimePath]);
    }
    File('$sdk/bin/dartaotruntime').copySync(runtimePath);
    await run('chmod', ['u+w', runtimePath]);

    final files = <String>['dartaotruntime', 'helper.aot'];
    final libraries = <String, String>{};
    final provenance = <Map<String, String>>[];
    final environment = <String, String>{
      'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      'LC_ALL': 'C',
      'LD_LIBRARY_PATH': '',
      'LD_PRELOAD': '',
      'LD_AUDIT': '',
    };
    Future<void> record(String name, String path) async {
      provenance.add({
        'name': name,
        'source': File(path).resolveSymbolicLinksSync(),
        'sha256': (await run('sha256sum', [
          path,
        ], environment: environment)).stdout.toString().split(' ').first,
      });
    }

    await record('dartaotruntime', '$sdk/bin/dartaotruntime');
    await record('helper.aot', snapshot.path);
    String sonameFor(String line, String resolved) {
      if (resolved.endsWith('/ld-linux-x86-64.so.2')) {
        return 'ld-linux-x86-64.so.2';
      }
      final match = RegExp(r'^\s*(\S+)\s+=>').firstMatch(line);
      if (match != null) return match.group(1)!;
      return resolved.split('/').last;
    }

    final systemdLibdir = (await run(
      pkgConfig,
      ['--variable=libdir', 'libsystemd'],
      environment: {
        ...environment,
        if (Platform.environment['PKG_CONFIG_PATH'] != null)
          'PKG_CONFIG_PATH': Platform.environment['PKG_CONFIG_PATH']!,
        if (Platform.environment['PKG_CONFIG_LIBDIR'] != null)
          'PKG_CONFIG_LIBDIR': Platform.environment['PKG_CONFIG_LIBDIR']!,
      },
    )).stdout.toString().trim();
    final systemd = File('$systemdLibdir/libsystemd.so.0');
    if (!systemd.existsSync()) {
      throw StateError('pkg-config did not provide libsystemd.so.0');
    }

    Future<void> dependencies(String file) async {
      final result = await run(ldd, [file], environment: environment);
      for (final line in '${result.stdout}'.split('\n')) {
        final match = RegExp(r'=>\s+(\S+)').firstMatch(line);
        final path =
            match?.group(1) ??
            (RegExp(r'^\s*(/[^ ]+)\s+\(').firstMatch(line)?.group(1));
        if (path == null || !path.startsWith('/')) {
          if (line.contains('not found')) {
            throw StateError('unresolved dependency in $file: $line');
          }
          continue;
        }
        final resolved = File(path).resolveSymbolicLinksSync();
        final trusted =
            resolved.startsWith('$sdk/') ||
            resolved.startsWith('/nix/store/') ||
            resolved.startsWith('/lib/') ||
            resolved.startsWith('/lib64/') ||
            resolved.startsWith('/usr/lib/');
        if (!trusted) {
          throw StateError('dependency outside SDK/system roots: $resolved');
        }
        final name = sonameFor(line, resolved);
        if (!RegExp(r'^[A-Za-z0-9_+.-]+$').hasMatch(name) ||
            name == '.' ||
            name == '..') {
          throw StateError('Unsafe bundled library filename: $name');
        }
        final previous = libraries[name];
        if (previous != null && previous != resolved) {
          final oldHash = await run('sha256sum', [
            previous,
          ], environment: environment);
          final newHash = await run('sha256sum', [
            resolved,
          ], environment: environment);
          if (oldHash.stdout.toString().split(' ').first !=
              newHash.stdout.toString().split(' ').first) {
            throw StateError('conflicting files claim library name $name');
          }
        } else if (previous == null) {
          libraries[name] = resolved;
          await dependencies(resolved);
        }
      }
    }

    await dependencies('${output.path}/dartaotruntime');
    await dependencies(systemd.path);
    libraries['libsystemd.so.0'] = systemd.resolveSymbolicLinksSync();
    for (final entry in libraries.entries) {
      final name = entry.key;
      final library = entry.value;
      final destination = File('${output.path}/lib/$name');
      destination.parent.createSync(recursive: true);
      if (destination.existsSync()) {
        await run('chmod', ['u+w', destination.path], environment: environment);
      }
      File(library).copySync(destination.path);
      await run('chmod', ['u+w', destination.path], environment: environment);
      await run(patchelf, [
        '--remove-rpath',
        destination.path,
      ], environment: environment);
      files.add('lib/$name');
      await record('lib/$name', library);
    }
    await run(patchelf, [
      '--remove-rpath',
      '${output.path}/dartaotruntime',
    ], environment: environment);
    File('${output.path}/manifest.txt')
        .writeAsStringSync('${files.join('\n')}\n');
    File('${output.path}/provenance.json')
        .writeAsStringSync(jsonEncode({'files': provenance}));

    final manifest = File('${output.path}/bundled_dart_manifest.h');
    final objects = <String>[];
    final declarations = StringBuffer();
    final entries = StringBuffer();
    for (var index = 0; index < files.length; index++) {
      final relative = files[index];
      final objectName = 'bundle_$index.o';
      await run(objcopy, [
        '-I',
        'binary',
        '-O',
        'elf64-x86-64',
        '-B',
        'i386:x86-64',
        '--rename-section',
        '.data=.rodata,alloc,load,readonly,data,contents',
        relative,
        objectName,
      ], workingDirectory: output.path);
      final prefix =
          '_binary_${relative.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}';
      final renamedName = 'bundle_${index}_renamed.o';
      final renamed = '${output.path}/$renamedName';
      await run(objcopy, [
        '--redefine-sym',
        '${prefix}_start=legion_bundle_${index}_start',
        '--redefine-sym',
        '${prefix}_end=legion_bundle_${index}_end',
        objectName,
        renamedName,
      ], workingDirectory: output.path);
      objects.add(renamed);
      declarations.writeln(
        'extern const unsigned char legion_bundle_${index}_start[];',
      );
      declarations.writeln(
        'extern const unsigned char legion_bundle_${index}_end[];',
      );
      final executable =
          relative == 'dartaotruntime' ||
          relative == 'lib/ld-linux-x86-64.so.2';
      entries.writeln(
        '  {"$relative", legion_bundle_${index}_start, legion_bundle_${index}_end, ${executable ? '0500' : '0400'}},',
      );
    }
    await run(linker, ['-r', '-o', '${output.path}/bundle.o', ...objects]);
    manifest.writeAsStringSync('''
#pragma once
#include <cstddef>
#include <sys/stat.h>
struct LegionBundledDartFile {
  const char *name;
  const unsigned char *start;
  const unsigned char *end;
  mode_t mode;
};
$declarations
static const LegionBundledDartFile legion_bundled_dart_files[] = {
$entries
};
static const size_t legion_bundled_dart_file_count =
    sizeof(legion_bundled_dart_files) / sizeof(legion_bundled_dart_files[0]);
''');
  } on Object catch (error) {
    stderr.writeln('build_dart_helper_bundle: $error');
    exitCode = 1;
  }
}
