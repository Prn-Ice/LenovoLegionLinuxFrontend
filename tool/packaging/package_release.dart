// Build the Linux app and archive the sources used by that build.
import 'dart:io';

import 'release_source/linux_build.dart';
import 'release_source/source_archive.dart';

Future<void> main(List<String> arguments) async {
  try {
    final root = File.fromUri(Platform.script).parent.parent.parent;
    final archive = releaseSourceArchive(arguments, root);
    final release = await buildLinuxRelease(root);
    await packageReleaseSource(root, release.bundle, archive, release.record);
    stdout.writeln('Packaged release source: ${archive.path}');
  } catch (error) {
    stderr.writeln('Release source: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

File releaseSourceArchive(List<String> arguments, Directory root) {
  final path = switch (arguments) {
    [] => 'build/release/legion-frontend-source.tar.gz',
    ['--output', final String path] when !path.startsWith('--') => path,
    _ => throw const FormatException(
      'Usage: dart tool/packaging/package_release.dart [--output archive.tar.gz]',
    ),
  };
  return File.fromUri(root.uri.resolve(path));
}
