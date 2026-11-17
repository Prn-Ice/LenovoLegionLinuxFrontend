{ pkgs, image }:
let
  fixtures = pkgs.callPackage ./fixtures.nix { };
in
pkgs.testers.runNixOSTest {
  name = "legion-appimage-nixos";
  nodes.machine = {
    security.polkit.enable = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id != "org.freedesktop.systemd1.manage-units") return;
        if (subject.user == "approved") {
          if (polkit.spawn(["${pkgs.coreutils}/bin/cat", "/run/legion-gui-approval"]).trim() == "deny")
            return polkit.Result.NO;
          return polkit.Result.YES;
        }
        if (subject.user == "denied") return polkit.Result.NO;
        if (subject.user == "challenge") return polkit.Result.AUTH_ADMIN;
      });
    '';
    users.users.approved = {
      isNormalUser = true;
      uid = 1000;
    };
    users.users.denied.isNormalUser = true;
    users.users.challenge.isNormalUser = true;
    programs.appimage.enable = true;
    environment.etc."legion-control-lifecycle-test-vm".text =
      "legion-control-disposable-lifecycle-vm\n";
    environment.etc."legion-vm-tests".source = ./.;
    environment.systemPackages = [
      fixtures
      pkgs.util-linux
      pkgs.xvfb-run
      pkgs.xdotool
      pkgs.xorg.xprop
      pkgs.sway
      pkgs.grim
      pkgs.jq
      pkgs.imagemagick
      (pkgs.tesseract.override { enableLanguages = [ "eng" ]; })
    ];
    hardware.graphics.enable = true;
    virtualisation.memorySize = 3072;
    virtualisation.cores = 2;
  };
  # Keep only the upstream driver's command and evidence-transfer bridge here.
  testScript = ''
    start_all()
    try:
        machine.succeed("bash /etc/legion-vm-tests/appimage_nixos.sh ${image} ${fixtures}", timeout=1800)
    finally:
        machine.copy_from_machine("/home/approved/gui.log")
        machine.copy_from_machine("/home/approved/wayland.log")
        machine.copy_from_machine("/home/approved/wayland-launcher.log")
        machine.copy_from_machine("/home/approved/sway.log")
        machine.copy_from_machine("/home/approved/wayland-diagnostics")
        machine.copy_from_machine("/home/approved/gui-evidence")
  '';
}
