# Legion Telemetry Service

`legion-telemetry-service` is a root-owned, read-only D-Bus service that turns
the kernel's restricted RAPL energy counter into cached CPU package power. It
never writes hardware state and does not use Polkit while sampling.

The Linux release bundle contains:

- `libexec/legion-telemetry-service`
- `lib/systemd/system/legion-telemetry.service`
- `share/dbus-1/system.d/io.github.prnice.LegionTelemetry1.conf`
- `lib/sysusers.d/legion-telemetry.conf`

A system package must install those files at their matching `/usr` locations,
run `systemd-sysusers`, add the desktop user to the `legion-telemetry` group,
and enable `legion-telemetry.service`. Group membership takes effect on the
next login. This is the only administrative setup; normal reads never request
authentication.

The service exposes only `GetSnapshot` on
`io.github.prnice.LegionTelemetry1`. Raw energy counters and arbitrary file
access are not part of the API.

## NixOS

Import `packaging/nixos/legion-telemetry.nix` into the system configuration,
then enable the service and list the desktop users that may read it:

```nix
services.legionTelemetry = {
  enable = true;
  users = [ "your-user" ];
};
```

Rebuild the system and start a new login session so the supplementary group is
present. The module builds the helper from this source tree and uses its Nix
store path directly.
