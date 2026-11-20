/// Connection details reported by an approved app helper launch.
/// The Linux host verifies the unit and socket credentials before connecting.
class ControlEndpoint {
  const ControlEndpoint({
    required this.address,
    required this.unit,
    required this.helperPid,
    required this.busName,
    this.cliPath,
  });

  final String address;
  final String unit;
  final int helperPid;
  final String busName;
  final String? cliPath;
}
