{ pkgs, frontend }:
let
  fixtures = pkgs.callPackage ./fixtures.nix { };
in
pkgs.testers.runNixOSTest {
  name = "legion-frontend-package";
  nodes.machine = {
    security.polkit.enable = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" && subject.user == "approved") {
          return polkit.Result.YES;
        }
      });
    '';
    users.users.approved = {
      isNormalUser = true;
      uid = 1000;
    };
    environment.etc."legion-control-lifecycle-test-vm".text =
      "legion-control-disposable-lifecycle-vm\n";
    environment.etc."legion-vm-tests".source = ./.;
    environment.systemPackages = [
      frontend
      fixtures
      pkgs.util-linux
      pkgs.xvfb-run
      pkgs.xdotool
      pkgs.imagemagick
      (pkgs.tesseract.override { enableLanguages = [ "eng" ]; })
    ];
    hardware.graphics.enable = true;
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
  };
  # The upstream driver supplies the VM command bridge.
  testScript = ''
    start_all()
    machine.succeed("bash /etc/legion-vm-tests/frontend_package.sh ${frontend}", timeout=420)
  '';
}
