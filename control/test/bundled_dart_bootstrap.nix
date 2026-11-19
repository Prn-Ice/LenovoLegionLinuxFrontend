{ pkgs, dart }:
let
  source = pkgs.lib.fileset.toSource {
    root = ../../experiments;
    fileset = pkgs.lib.fileset.unions [
      ../../experiments/run_bundled_helper.dart
      ../../experiments/check_bundled_dart_runtime.dart
    ];
  };
  bundle = pkgs.runCommand "legion-dart-runtime-bundle" { nativeBuildInputs = [ dart ]; } ''
    export HOME="$TMPDIR"
    mkdir -p "$out/lib"
    dart compile aot-snapshot ${source}/run_bundled_helper.dart -o "$out/helper.aot"
    cp ${dart}/bin/dartaotruntime "$out/dartaotruntime"
    for name in ld-linux-x86-64.so.2 libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0; do
      cp -L ${pkgs.glibc}/lib/"$name" "$out/lib/$name"
    done
  '';
  probe = pkgs.pkgsStatic.callPackage ./bundled_dart_package.nix { inherit bundle; };
  invalidBundle = pkgs.runCommand "legion-invalid-dart-runtime-bundle" { } ''
    mkdir -p "$out"
    cp -r ${bundle}/. "$out/"
    chmod u+w "$out/helper.aot"
    printf 'invalid test snapshot\n' > "$out/helper.aot"
  '';
  invalidProbe = pkgs.pkgsStatic.callPackage ./bundled_dart_package.nix {
    bundle = invalidBundle;
  };
in
pkgs.testers.runNixOSTest {
  name = "legion-bundled-dart-bootstrap";
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
    environment.etc."legion-invalid-dart-probe".source =
      "${invalidProbe}/bin/bundled-dart-bootstrap-probe";
    environment.systemPackages = [
      probe
      pkgs.util-linux
    ];
    systemd.services.legion-bootstrap-gate.serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "legion-dart-startup-gate" ''
        trap 'exit 0' USR1
        ${pkgs.coreutils}/bin/sleep 30 &
        wait
      '';
      TimeoutStartSec = 35;
    };
    virtualisation.memorySize = 1024;
  };
  # The upstream driver starts the VM; the guest checks use the shared shell helpers.
  testScript = ''
    start_all()
    try:
        machine.succeed("bash /etc/legion-vm-tests/bundled_dart_bootstrap.sh ${probe} ${invalidProbe}", timeout=300)
    finally:
        machine.copy_from_machine("/tmp/bundled-dart-tests.log")
  '';
}
