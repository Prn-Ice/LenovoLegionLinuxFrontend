{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.legionTelemetry;
  control = config.services.legionControl;
in
{
  options.services.legionTelemetry = {
    enable = lib.mkEnableOption "Lenovo Legion package power telemetry";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../telemetry/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./telemetry/package.nix { }";
      description = "Package providing legion-telemetry-service.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = "Users allowed to read package power over D-Bus.";
    };
  };

  options.services.legionControl = {
    enable = lib.mkEnableOption "Lenovo Legion privileged hardware control";

    package = lib.mkOption {
      type = lib.types.package;
      default = cfg.package;
      description = "Package providing legion-control-service.";
    };

    backendPackage = lib.mkOption {
      type = lib.types.package;
      description = "Package providing legion_cli.";
      example = lib.literalExpression "pkgs.lenovo-legion";
    };

    reconcileGraphicsAtBoot = lib.mkEnableOption "graphics-mode reconciliation before graphical login";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
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
    })
    (lib.mkIf control.enable {
      services.dbus.packages = [ control.package ];
      security.polkit.enable = true;
      environment.systemPackages = [ control.package ];

      systemd.services.legion-control = {
        description = "Lenovo Legion privileged hardware control";
        wantedBy = [ "multi-user.target" ];
        after = [ "dbus.service" ];
        wants = [ "dbus.service" ];
        # legion_cli uses these commands internally. Keep the root service PATH
        # limited to immutable store paths rather than inheriting a user PATH.
        path = [
          pkgs.bashNonInteractive
          pkgs.e2fsprogs
          pkgs.util-linux
        ];
        serviceConfig = {
          Type = "dbus";
          BusName = "io.github.prnice.LegionControl1";
          ExecStart = "${control.package}/libexec/legion-control-service --cli ${control.backendPackage}/bin/legion_cli --systemctl ${pkgs.systemd}/bin/systemctl";
          User = "root";
          Restart = "on-failure";
          RestartSec = 2;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
          RestrictNamespaces = true;
          SystemCallArchitectures = "native";
          SystemCallErrorNumber = "EPERM";
          SystemCallFilter = [ "@system-service" ];
        };
      };
    })
    (lib.mkIf (control.enable && control.reconcileGraphicsAtBoot) {
      boot.kernelModules = [ "legion_laptop" ];

      systemd.services.legion-graphics-reconcile = {
        description = "Reconcile Lenovo Legion graphics topology";
        wantedBy = [ "graphical.target" ];
        requiredBy = [ "display-manager.service" ];
        before = [ "display-manager.service" ];
        after = [
          "local-fs.target"
          "systemd-modules-load.service"
        ];
        requires = [ "systemd-modules-load.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${control.backendPackage}/bin/legion_cli --donotexpecthwmon graphics-mode reconcile --json";
          TimeoutStartSec = 40;
          RemainAfterExit = true;
          User = "root";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [ "AF_UNIX" ];
          RestrictNamespaces = true;
          SystemCallArchitectures = "native";
          SystemCallErrorNumber = "EPERM";
          SystemCallFilter = [ "@system-service" ];
        };
      };
    })
  ];
}
