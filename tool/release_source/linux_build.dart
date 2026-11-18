import 'dart:io';

import '../bundle_notices.dart';
import '../package_linux.dart' show requirePrivilegedControlHelper;
import 'build_record.dart';
import 'source_files.dart';
import 'source_inputs.dart';

typedef BuiltLinuxRelease = ({Directory bundle, ReleaseBuildRecord record});

/// Builds the desktop and its privileged helper from the recorded inputs.
Future<BuiltLinuxRelease> buildLinuxRelease(Directory root) async {
  requireCleanSourceTree(root);
  final flutter = _FlutterBuild(root);
  await flutter.resolveLockedDependencies();
  final inputs = await captureReleaseInputs(root);
  await flutter.buildLinuxRelease();
  final bundle = Directory('${root.path}/build/linux/x64/release/bundle');
  await bundleNotices(root, bundle);
  return (bundle: bundle, record: await recordReleaseBuild(bundle, inputs));
}

/// Records every shipped file, including the helper and native libraries.
Future<ReleaseBuildRecord> recordReleaseBuild(
  Directory bundle,
  ReleaseInputs inputs, {
  bool staticPortableHelper = false,
}) async {
  requirePrivilegedControlHelper(bundle);
  return ReleaseBuildRecord(
    inputs: inputs,
    binarySha256: await releaseFileSha256(File('${bundle.path}/lib/libapp.so')),
    bundle: await inventoryReleaseTree(bundle),
    staticPortableHelper: staticPortableHelper,
  );
}

class _FlutterBuild {
  const _FlutterBuild(this.root);

  final Directory root;

  Future<void> resolveLockedDependencies() =>
      _run(['pub', 'get', '--enforce-lockfile']);

  Future<void> buildLinuxRelease() =>
      _run(['build', 'linux', '--release', '--no-pub']);

  Future<void> _run(List<String> arguments) async {
    final process = await Process.start(
      'flutter',
      arguments,
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
    );
    if (await process.exitCode != 0) {
      throw StateError('Flutter ${arguments.first} failed.');
    }
  }
}
