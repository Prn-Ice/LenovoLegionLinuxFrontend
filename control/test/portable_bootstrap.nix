{ pkgs }:

let
  fixtures = pkgs.callPackage ./fixtures.nix { };
  probe = pkgs.callPackage ./bootstrap-package.nix { inherit fixtures; };
in
pkgs.testers.runNixOSTest {
  name = "legion-portable-bootstrap";
  nodes.machine = {
    security.polkit.enable = true;
    users.users = {
      approved = {
        isNormalUser = true;
        uid = 1000;
      };
      denied = {
        isNormalUser = true;
        uid = 1001;
      };
      challenge = {
        isNormalUser = true;
        uid = 1002;
      };
    };
    # This policy replaces desktop authentication only inside the disposable VM.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id != "org.freedesktop.systemd1.manage-units") return;
        if (subject.user == "approved") return polkit.Result.YES;
        if (subject.user == "denied") return polkit.Result.NO;
        if (subject.user == "challenge") return polkit.Result.AUTH_ADMIN;
      });
    '';
    environment.etc."legion-control-lifecycle-test-vm".text =
      "legion-control-disposable-lifecycle-vm\n";
    environment.etc."legion-vm-tests".source = ./.;
    environment.systemPackages = [
      probe
      fixtures
      pkgs.util-linux
    ];
    systemd.services.legion-bootstrap-gate.serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "legion-bootstrap-test-gate" ''
        trap 'exit 0' USR1
        ${pkgs.coreutils}/bin/sleep 30 &
        wait
      '';
      TimeoutStartSec = 35;
    };
    virtualisation.memorySize = 1024;
  };
  # Python is required by the upstream driver, not by the guest scenarios.
  testScript = ''
    start_all()
    machine.succeed("bash /etc/legion-vm-tests/portable_bootstrap.sh ${probe} ${fixtures}", timeout=900)
  '';
}
