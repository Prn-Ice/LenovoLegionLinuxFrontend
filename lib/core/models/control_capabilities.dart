/// Operations advertised by the selected control helper.
enum ControlCapability {
  interactiveControl,
  persistentServices,
  nextBootGraphics,
}

class ControlCapabilities {
  ControlCapabilities({
    required this.protocolVersion,
    required Iterable<ControlCapability> supported,
  }) : supported = Set.unmodifiable(supported);

  static const currentProtocolVersion = 1;

  final int protocolVersion;
  final Set<ControlCapability> supported;
}
