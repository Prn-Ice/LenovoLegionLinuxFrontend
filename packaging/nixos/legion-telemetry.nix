{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.legionTelemetry;
  control = config.services.legionControl;
  nvidiaPciPresent = pkgs.writeShellScript "nvidia-pci-present" ''
    for vendor in /sys/bus/pci/devices/*/vendor; do
      if [[ -r "$vendor" ]] && [[ "$(<"$vendor")" == "0x10de" ]]; then
        exit 0
      fi
    done
    exit 1
  '';
  graphicsSleepReconcile = pkgs.writeShellScript "legion-graphics-sleep-reconcile" ''
    if [[ "$1" != "post" ]]; then
      exit 0
    fi

    exec ${pkgs.coreutils}/bin/timeout --foreground --kill-after=5s 40s \
      ${control.backendPackage}/bin/legion_cli \
      --donotexpecthwmon graphics-mode reconcile --json
  '';
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

    reconcileGraphicsAfterSleep = lib.mkOption {
      type = lib.types.bool;
      default = control.reconcileGraphicsAtBoot;
      defaultText = lib.literalExpression "config.services.legionControl.reconcileGraphicsAtBoot";
      description = ''
        Reconcile the selected graphics topology after the system returns from
        suspend or hibernate, before systemd thaws user sessions.
      '';
    };
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
        path = [ pkgs.bash ];
        wantedBy = [ "graphical.target" ];
        requiredBy = [ "display-manager.service" ];
        before = [
          "display-manager.service"
          "nvidia-container-toolkit-cdi-generator.service"
        ];
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

      systemd.services.nvidia-container-toolkit-cdi-generator =
        lib.mkIf config.hardware.nvidia-container-toolkit.enable
          {
            before = [ "docker.service" ];
            serviceConfig.ExecCondition = nvidiaPciPresent;
          };
    })
    (lib.mkIf (control.enable && control.reconcileGraphicsAfterSleep) {
      environment.etc."systemd/system-sleep/legion-graphics-reconcile".source = graphicsSleepReconcile;
    })
  ];
}
