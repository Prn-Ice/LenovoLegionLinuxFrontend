{ pkgs }:

let
  service = pkgs.callPackage ../../control/package.nix { };
  fixtures = pkgs.callPackage ./fixtures.nix { };
  probe = pkgs.callPackage ./bootstrap-package.nix { inherit fixtures; };
in
pkgs.testers.runNixOSTest {
  name = "legion-control-lifecycle";
  nodes.machine = {
    imports = [ ../../packaging/nixos/legion-control.nix ];
    services.legionControl = {
      enable = true;
      package = service;
      backendPackage = fixtures;
      nextBootGraphics = true;
      reconcileGraphicsAtBoot = true;
      reconcileGraphicsAfterHibernate = false;
    };
    # Exercise next-boot requests without graphics transitions or hardware drivers.
    systemd.services.legion-graphics-reconcile.enable = false;
    boot.kernelModules = pkgs.lib.mkForce [ ];
    environment.etc."legion-control-lifecycle-test-vm".text =
      "legion-control-disposable-lifecycle-vm\n";
    environment.etc."legion-vm-tests".source = ./.;
    environment.systemPackages = [
      fixtures
      probe
      pkgs.util-linux
      pkgs.procps
      pkgs.jq
    ];
    # Deterministic VM policy still exercises the real Authorize method.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" && subject.user == "portable") {
          return polkit.Result.YES;
        }
        if (action.id == "io.github.prnice.legion-control.manage" && subject.user == "root") {
          return polkit.Result.YES;
        }
      });
    '';
    users.users.portable = {
      isNormalUser = true;
      uid = 1000;
    };
    virtualisation.memorySize = 1024;
  };
  # The upstream NixOS driver is Python; all project scenarios run in the guest.
  testScript = ''
    start_all()
    machine.succeed("bash /etc/legion-vm-tests/control_lifecycle.sh ${probe}", timeout=600)
  '';
}
