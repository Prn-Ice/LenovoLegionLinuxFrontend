// Shared desktop layout and ELF checks for distro packages and AppImages.
import 'dart:io';

const appId = 'io.github.prnice.legion_linux_frontend';

Future<void> stageDesktopPackage(
  Directory root,
  Directory bundle,
  Directory staging,
) async {
  if (staging.existsSync()) {
    throw StateError('Staging directory already exists.');
  }
  final appBundle = Directory('${staging.path}/usr/lib/legion_frontend');
  await appBundle.create(recursive: true);
  await runPackagingCommand('cp', ['-a', '${bundle.path}/.', appBundle.path]);
  for (final path in [
    'lib/systemd',
    'lib/sysusers.d',
    'share/dbus-1',
    'share/polkit-1',
  ]) {
    final directory = Directory('${appBundle.path}/$path');
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
  for (final name in ['legion-telemetry-service', 'legion-control-service']) {
    final file = File('${appBundle.path}/libexec/$name');
    if (file.existsSync()) await file.delete();
  }
  if (!File('${appBundle.path}/libexec/legion-portable-control').existsSync()) {
    throw StateError('The desktop bundle has no portable helper.');
  }
  final packaging = '${root.path}/packaging/appimage';
  for (final entry in {
    'applications/$appId.desktop': '$packaging/$appId.desktop',
    'metainfo/$appId.metainfo.xml': '$packaging/$appId.metainfo.xml',
    'icons/hicolor/scalable/apps/$appId.svg':
        '${root.path}/assets/branding/legion_app.svg',
    'icons/hicolor/256x256/apps/$appId.png':
        '${root.path}/assets/branding/legion_app.png',
    'licenses/legion_frontend/branding/README.md':
        '${root.path}/assets/branding/README.md',
  }.entries) {
    final target = File('${staging.path}/usr/share/${entry.key}');
    await target.parent.create(recursive: true);
    await File(entry.value).copy(target.path);
  }
}

Future<Map<String, Object>> inspectDesktopPackage(Directory appdir) async {
  final libraries = <String, Object>{};
  await for (final file in appdir.list(recursive: true, followLinks: false)) {
    if (file is! File) continue;
    final input = await file.open();
    final magic = await input.read(4);
    await input.close();
    if (magic.length != 4 ||
        magic[0] != 0x7f ||
        String.fromCharCodes(magic.skip(1)) != 'ELF') {
      continue;
    }
    final relative = file.path.substring(appdir.path.length + 1);
    final elf = await runPackagingCommand('readelf', ['-lW', '-dW', file.path]);
    if (elf.contains('/nix/store/') ||
        (relative.endsWith('/libexec/legion-portable-control') &&
            RegExp(r'\((?:RPATH|RUNPATH)\)').hasMatch(elf))) {
      throw StateError('Unsafe library search paths in $relative');
    }
    libraries[relative] = [
      for (final match in RegExp(
        r'Shared library: \[([^\]]+)\]',
      ).allMatches(elf))
        match.group(1)!,
    ];
  }
  return libraries;
}

Future<String> runPackagingCommand(
  String command,
  List<String> arguments,
) async {
  final result = await Process.run(
    command,
    arguments,
    environment: {'LC_ALL': 'C'},
  );
  if (result.exitCode != 0) {
    throw StateError('$command failed: ${result.stderr}');
  }
  return result.stdout as String;
}

Future<String> fileSha256(File file) async => (await runPackagingCommand(
  'sha256sum',
  ['--binary', '--zero', '--', file.path],
)).substring(0, 64);
