// Keep package versions and download filenames consistent across release tools.
String debianVersion(String version) {
  final match = RegExp(
    r'^(\d+\.\d+\.\d+)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.]+))?$',
  ).firstMatch(version);
  if (match == null) {
    throw FormatException('Unsupported release version: $version');
  }
  return '${match[1]}${match[2] == null ? '' : '~${match[2]}'}${match[3] == null ? '' : '+${match[3]}'}-1';
}

String debianFileName(String version) {
  // GitHub renames '~' on upload. Debian reads its version from package metadata.
  final downloadVersion = debianVersion(version).replaceFirst('~', '-');
  return 'legion-linux-frontend_${downloadVersion}_amd64.deb';
}
