{ config, lib, pkgs, ... }:

let
  cfg = config.services.legionTelemetry;
in
{
  options.services.legionTelemetry = {
    enable = lib.mkEnableOption "Lenovo Legion package power telemetry";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../telemetry/package.nix { };
      defaultText = lib.literalExpression
        "pkgs.callPackage ./telemetry/package.nix { }";
      description = "Package providing legion-telemetry-service.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = "Users allowed to read package power over D-Bus.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.legion-telemetry = { };
    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = [ "legion-telemetry" ];
    });

    services.dbus.packages = [ cfg.package ];

    systemd.services.legion-telemetry = {
      description = "Lenovo Legion package power telemetry";
      wantedBy = [ "multi-user.target" ];
      after = [ "dbus.service" ];
      wants = [ "dbus.service" ];
      serviceConfig = {
        Type = "dbus";
        BusName = "io.github.prnice.LegionTelemetry1";
        ExecStart = "${cfg.package}/libexec/legion-telemetry-service";
        User = "root";
        Restart = "on-failure";
        RestartSec = 2;
        CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" ];
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        ReadOnlyPaths = [ "/sys/class/powercap" ];
        RestrictAddressFamilies = [ "AF_UNIX" ];
        RestrictNamespaces = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
      };
    };
  };
}
