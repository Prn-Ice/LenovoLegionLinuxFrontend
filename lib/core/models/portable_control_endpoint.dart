/// Connection details reported by an approved portable helper launch.
/// The Linux host verifies the unit and socket credentials before connecting.
class PortableControlEndpoint {
  const PortableControlEndpoint({
    required this.address,
    required this.unit,
    required this.helperPid,
  });

  final String address;
  final String unit;
  final int helperPid;
}
