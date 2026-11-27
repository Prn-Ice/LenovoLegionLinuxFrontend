// Bundle the desktop runtime and archive the exact Ubuntu package sources.
import 'dart:convert';
import 'dart:io';

import 'packaging_files.dart';

// Keep loader, ABI, and graphics-driver interfaces supplied by the host. GTK,
// GLib, Pango, font rendering, and their remaining dependencies are bundled.
const hostLibraries = {
  'ld-linux-x86-64.so.2',
  'libc.so.6',
  'libdl.so.2',
  'libm.so.6',
  'libmvec.so.1',
  'libpthread.so.0',
  'libresolv.so.2',
  'librt.so.1',
  'libutil.so.1',
  'libstdc++.so.6',
  'libgcc_s.so.1',
  'libGL.so.1',
  'libEGL.so.1',
  'libGLESv2.so.2',
  'libGLdispatch.so.0',
  'libGLX.so.0',
  'libOpenGL.so.0',
  'libdrm.so.2',
  'libgbm.so.1',
  'libglapi.so.0',
  'libX11.so.6',
  'libX11-xcb.so.1',
  'libxcb.so.1',
  'libwayland-client.so.0',
};

String runtimeCommand(
  String executable,
  List<String> arguments, {
  Directory? directory,
  Map<String, String> environment = const {},
}) => packagingCommand(
  executable,
  arguments,
  workingDirectory: directory?.path,
  environment: {
    ...Map<String, String>.from(Platform.environment)
      ..remove('LD_LIBRARY_PATH')
      ..remove('LD_PRELOAD')
      ..remove('LD_AUDIT'),
    'LC_ALL': 'C',
    ...environment,
  },
);

bool isElf(File file) {
  final source = file.openSync();
  try {
    return sameJson(source.readSync(4), [0x7f, 0x45, 0x4c, 0x46]);
  } finally {
    source.closeSync();
  }
}

Map<String, File> dependencies(String output) {
  final result = <String, File>{};
  for (final line in const LineSplitter().convert(output)) {
    if (line.contains('=> not found')) {
      throw StateError('Unresolved desktop dependency: ${line.trim()}');
    }
    final match = RegExp(r'^\s*(\S+) => (/.*?) \(0x[0-9a-f]+\)')
        .firstMatch(line);
    if (match != null) result[match[1]!] = File(match[2]!);
  }
  return result;
}

bool within(String path, Directory directory) =>
    path == directory.absolute.path ||
    path.startsWith('${directory.absolute.path}/');

List<FileSystemEntity> sortedEntries(Directory directory) =>
    directory.listSync()..sort((a, b) => a.path.compareTo(b.path));

Map<String, String> archiveHashes(Directory directory) => {
  for (final path in sortedEntries(directory))
    fileName(path): packagingSha256(File(path.path)),
};

class RuntimeBundle {
  RuntimeBundle(this.appdir, this.inputs)
    : bundle = Directory('${appdir.path}/usr/lib/legion_frontend');

  final Directory appdir;
  final Directory bundle;
  final Directory inputs;
  final packages = <String, Map<String, Object>>{};
  final sources = <String, Map<String, Object>>{};
  final files = <String, Map<String, Object>>{};
  final requiredHostLibraries = {
    'ld-linux-x86-64.so.2',
    'libEGL.so.1',
    'libGLESv2.so.2',
  };
  Map<String, Object> cleanup = {};
  Map<String, Object> staticLibraries = {};

  String package(String name) {
    if (packages.containsKey(name)) return name;
    final data = runtimeCommand('dpkg-query', [
      '-W',
      '-f',
      r'${binary:Package}\t${Version}\t${source:Package}\t${source:Version}',
      name,
    ]).split('\t');
    if (data.length != 4) {
      throw StateError('Invalid package metadata for $name');
    }
    final binary = data[0], version = data[1];
    final source = data[2].isEmpty ? binary.split(':').first : data[2];
    final sourceVersion = data[3].isEmpty ? version : data[3];
    packages[binary] = {
      'version': version,
      'source': source,
      'source_version': sourceVersion,
    };
    final previous = sources[source];
    if (previous != null && previous['version'] != sourceVersion) {
      throw StateError('Mixed source versions for $source');
    }
    if (previous == null) {
      final directory = Directory('${inputs.path}/sources/$source')
        ..createSync(recursive: true);
      runtimeCommand('apt-get', [
        'source',
        '--download-only',
        '--only-source',
        '$source=$sourceVersion',
      ], directory: directory);
      final archives = archiveHashes(directory);
      if (archives.isEmpty ||
          !archives.keys.any((name) => name.endsWith('.dsc'))) {
        throw StateError('Incomplete source download for $source');
      }
      sources[source] = {'version': sourceVersion, 'archives': archives};
    }
    final copyright = File(
      '/usr/share/doc/${binary.split(':').first}/copyright',
    );
    if (!copyright.existsSync()) {
      throw StateError('Missing copyright notice for $binary');
    }
    final target = File(
      '${bundle.path}/share/licenses/appimage-native/$binary/copyright',
    );
    target.parent.createSync(recursive: true);
    copyright.copySync(target.path);
    return binary;
  }

  String owner(File path) {
    final candidates = [path.path, path.resolveSymbolicLinksSync()];
    for (final candidate in candidates.toList()) {
      if (candidate.startsWith('/usr/')) {
        candidates.add(candidate.substring(4));
      } else if (['/lib/', '/bin/', '/sbin/'].any(candidate.startsWith)) {
        candidates.add('/usr$candidate');
      }
    }
    for (final candidate in candidates.toSet()) {
      final result = Process.runSync('dpkg-query', ['-S', candidate]);
      if (result.exitCode != 0) continue;
      for (final line in const LineSplitter().convert(
        result.stdout as String,
      )) {
        final separator = line.indexOf(': ');
        if (separator >= 0 && line.substring(separator + 2) == candidate) {
          return package(line.substring(0, separator));
        }
      }
    }
    throw StateError('No distro source owner for ${path.path}');
  }

  void copy(File source, File target, {String? packageName}) {
    final attribution = packageName == null
        ? owner(source)
        : package(packageName);
    if (target.existsSync() &&
        packagingSha256(target) != packagingSha256(source)) {
      throw StateError('Conflicting runtime file: ${target.path}');
    }
    target.parent.createSync(recursive: true);
    source.copySync(target.path);
    runtimeCommand('chmod', [
      source.statSync().mode & 0x49 != 0 ? '755' : '644',
      target.path,
    ]);
    files[target.absolute.path.substring(appdir.absolute.path.length + 1)] = {
      'sha256': packagingSha256(target),
      'package': attribution,
    };
  }

  void closure(List<File> roots) {
    final pending = roots.toList(), seen = <String>{};
    while (pending.isNotEmpty) {
      final binary = pending.removeLast();
      if (!seen.add(binary.path)) continue;
      final metadata = runtimeCommand('readelf', ['-dW', binary.path]);
      if (!metadata.contains('(NEEDED)')) continue;
      final output = runtimeCommand(
        'ldd',
        [binary.path],
        environment: {'LD_LIBRARY_PATH': '${bundle.path}/lib'},
      );
      for (final entry in dependencies(output).entries) {
        if (hostLibraries.contains(entry.key)) {
          requiredHostLibraries.add(entry.key);
          continue;
        }
        if (within(entry.value.resolveSymbolicLinksSync(), appdir)) {
          pending.add(entry.value);
          continue;
        }
        copy(entry.value, File('${bundle.path}/lib/${entry.key}'));
        pending.add(entry.value);
      }
    }
  }

  List<File> dataPackage(String name, String prefix) {
    package(name);
    final copied = <File>[];
    for (final path in const LineSplitter().convert(
      runtimeCommand('dpkg-query', ['-L', name]),
    )) {
      final source = File(path);
      if (path.startsWith('$prefix/') && source.existsSync()) {
        final target = File(
          '${appdir.path}/${path.replaceFirst(RegExp(r'^/+'), '')}',
        );
        copy(source, target, packageName: name);
        copied.add(target);
      }
    }
    if (copied.isEmpty) throw StateError('No runtime data from $name');
    return copied;
  }

  void staticHelper(Directory root) {
    package('libmount1');
    final source = sortedEntries(Directory('${inputs.path}/sources/util-linux'))
        .firstWhere((file) => file.path.endsWith('.dsc'));
    final helper = File('${bundle.path}/libexec/legion-control-helper');
    final build = Directory.systemTemp.createTempSync('static-helper-');
    try {
      final log = runtimeCommand('bash', [
        '${root.path}/tool/packaging/build_static_helper.sh',
        root.path,
        source.path,
        build.path,
        helper.path,
      ]);
      File('${inputs.path}/static-helper-build.log').writeAsStringSync(log);
      final cleanupElf = File('${build.path}/helper/legion_helper_cleanup');
      validateStaticElf(cleanupElf, cleanup: true);
      cleanupElf.copySync('${inputs.path}/helper-cleanup.elf');
      cleanup = {
        'sha256': packagingSha256(cleanupElf),
        'size': cleanupElf.lengthSync(),
      };
      final archives = <String, Object>{};
      for (final line in const LineSplitter().convert(log)) {
        if (!RegExp(r'^/\S+\.a$').hasMatch(line)) continue;
        final path = File(line);
        archives[fileName(path)] = {
          'sha256': packagingSha256(path),
          if (within(path.absolute.path, build))
            'source': 'util-linux'
          else
            'package': owner(path),
        };
      }
      if (!archives.containsKey('libc.a') ||
          !archives.containsKey('libglib-2.0.a')) {
        throw StateError('The static helper link trace is incomplete');
      }
      staticLibraries = archives;
    } finally {
      build.deleteSync(recursive: true);
    }
    validateStaticElf(helper);
  }

  void finish() {
    for (final entry in sources.entries) {
      final directory = Directory('${inputs.path}/sources/${entry.key}');
      if (!sameJson(archiveHashes(directory), entry.value['archives'])) {
        throw StateError(
          'Source archives changed during the build: ${entry.key}',
        );
      }
    }
    final notices = Directory(
      '${bundle.path}/share/licenses/appimage-native/common-licenses',
    )..createSync(recursive: true);
    runtimeCommand('cp', ['-rL', '/usr/share/common-licenses/.', notices.path]);
    final manifest = {
      'format': 1,
      'packages': packages,
      'sources': sources,
      'files': files,
      'host_libraries': requiredHostLibraries.toList()..sort(),
      'helper': {
        'linkage': 'static',
        'libraries': staticLibraries,
        'cleanup': cleanup,
      },
    };
    writePackagingJson(File('${inputs.path}/native-runtime.json'), manifest);
    writePackagingJson(
      File('${bundle.path}/share/licenses/appimage-native/native-runtime.json'),
      manifest,
    );
  }
}

void validateStaticElf(File file, {bool cleanup = false}) {
  if (cleanup && file.lengthSync() >= 64 * 1024) {
    throw StateError('The embedded cleanup ELF must stay below 64 KiB');
  }
  final metadata = runtimeCommand('readelf', ['-lW', '-dW', file.path]);
  validateStaticMetadata(metadata, cleanup: cleanup);
}

void validateStaticMetadata(String metadata, {bool cleanup = false}) {
  if (RegExp(r'INTERP|\((?:NEEDED|RPATH|RUNPATH)\)').hasMatch(metadata)) {
    throw StateError(
      cleanup
          ? 'The embedded cleanup ELF must be fully static'
          : 'The AppImage helper must be fully static',
    );
  }
}

void bundleRuntime(Directory root, Directory appdir, Directory inputs) {
  inputs.createSync(recursive: true);
  final runtime = RuntimeBundle(appdir, inputs);
  runtime.staticHelper(root);
  final desktop = runtime.bundle
      .listSync(recursive: true)
      .whereType<File>()
      .where(isElf)
      .toList();
  final modules = <File>[];
  final libraries = Directory('/usr/lib').listSync().whereType<Directory>();
  for (final library in libraries) {
    final pixbuf = Directory('${library.path}/gdk-pixbuf-2.0');
    if (!pixbuf.existsSync()) continue;
    for (final version in pixbuf.listSync().whereType<Directory>()) {
      final loaders = Directory('${version.path}/loaders');
      if (!loaders.existsSync()) continue;
      for (final source in sortedEntries(
        loaders,
      ).where((file) => file.path.endsWith('.so'))) {
        final target = File(
          '${runtime.bundle.path}/lib/pixbuf-loaders/${fileName(source)}',
        );
        runtime.copy(File(source.path), target);
        modules.add(target);
      }
    }
  }
  if (modules.isEmpty) throw StateError('No GTK image loaders found');
  final query = File(
    runtimeCommand('pkg-config', [
      '--variable=gdk_pixbuf_query_loaders',
      'gdk-pixbuf-2.0',
    ]).trim(),
  );
  final queryTarget = File(
    '${runtime.bundle.path}/libexec/gdk-pixbuf-query-loaders',
  );
  runtime.copy(query, queryTarget);
  final dconf = libraries
      .map((library) => File('${library.path}/gio/modules/libdconfsettings.so'))
      .firstWhere((file) => file.existsSync());
  final dconfTarget = File(
    '${runtime.bundle.path}/lib/gio/modules/libdconfsettings.so',
  );
  runtime.copy(dconf, dconfTarget);
  runtime.closure([...desktop, ...modules, queryTarget, dconfTarget]);
  runtimeCommand('gio-querymodules', [dconfTarget.parent.path]);
  for (final package in ['libgtk-3-common', 'gsettings-desktop-schemas']) {
    runtime.dataPackage(package, '/usr/share/glib-2.0/schemas');
  }
  runtimeCommand('glib-compile-schemas', [
    '${appdir.path}/usr/share/glib-2.0/schemas',
  ]);
  runtime.dataPackage('adwaita-icon-theme', '/usr/share/icons/Adwaita');
  runtime.dataPackage('hicolor-icon-theme', '/usr/share/icons/hicolor');
  runtime.dataPackage('fonts-dejavu-core', '/usr/share/fonts/truetype/dejavu');
  runtime.copy(
    File('/usr/bin/xdg-user-dir'),
    File('${appdir.path}/usr/bin/xdg-user-dir'),
  );
  final fontconfig = File('${appdir.path}/usr/etc/fonts/fonts.conf');
  fontconfig.parent.createSync(recursive: true);
  fontconfig.writeAsStringSync('''<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>usr/share/fonts</dir>
  <dir>/usr/share/fonts</dir>
  <dir>/usr/local/share/fonts</dir>
  <dir prefix="xdg">fonts</dir>
  <cachedir prefix="xdg">fontconfig</cachedir>
</fontconfig>
''');
  runtime.finish();
}

void main(List<String> args) {
  try {
    if (args.length != 4 || args[0] != '--appdir' || args[2] != '--inputs') {
      throw const FormatException(
        'Usage: dart tool/packaging/bundle_appimage_runtime.dart --appdir DIRECTORY --inputs DIRECTORY',
      );
    }
    bundleRuntime(
      File.fromUri(Platform.script).parent.parent.parent,
      Directory(args[1]).absolute,
      Directory(args[3]).absolute,
    );
  } catch (error) {
    stderr.writeln('AppImage runtime: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}
