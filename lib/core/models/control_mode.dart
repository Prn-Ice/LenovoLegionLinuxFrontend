/// Hardware access is selected once for each app process.
enum ControlMode {
  installedService('Installed service'),
  temporaryHelper('Temporary helper');

  const ControlMode(this.label);
  final String label;
}
