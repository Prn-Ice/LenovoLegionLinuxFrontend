# Legion Telemetry Service

`legion-telemetry-service` reads the kernel's restricted RAPL energy counter and
provides cached CPU package power over D-Bus. It runs as root and does not change
hardware settings.

The Linux release bundle contains:

- `libexec/legion-telemetry-service`
- `lib/systemd/system/legion-telemetry.service`
- `share/dbus-1/system.d/io.github.prnice.LegionTelemetry1.conf`
- `lib/sysusers.d/legion-telemetry.conf`

To install the service:

1. Install the bundled files under the matching `/usr` paths.
2. Run `systemd-sysusers`.
3. Add the desktop user to `legion-telemetry`.
4. Enable `legion-telemetry.service`.
5. Log out and back in.

Reading telemetry does not require an authentication prompt.

The D-Bus API provides one method: `io.github.prnice.LegionTelemetry1.GetSnapshot`.

## NixOS

Import `packaging/nixos/legion-telemetry.nix` into the system configuration,
then enable the service and list the desktop users that may read it:

```nix
services.legionTelemetry = {
  enable = true;
  users = [ "your-user" ];
};
```

Rebuild your system, then log out and back in to apply the group membership.
