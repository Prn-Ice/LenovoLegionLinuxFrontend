{
  stdenv,
  lib,
  cmake,
  pkg-config,
  glib,
  fixtures,
}:

stdenv.mkDerivation {
  pname = "legion-helper-bootstrap-probe";
  version = "1";
  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../control
      ../../packaging
    ];
  };
  nativeBuildInputs = [
    cmake
    pkg-config
  ];
  buildInputs = [
    glib
  ];
  preConfigure = "cd control";
  cmakeFlags = [
    "-DBUILD_TESTING=ON"
    "-DBUILD_HELPER_BOOTSTRAP_PROTOTYPE=ON"
    "-DBUILD_CONTROL_HELPER=ON"
    "-DCONTROL_TEST_CLI=${fixtures}/bin/legion_cli"
  ];
  buildPhase = ''
    runHook preBuild
    cmake --build . --target helper_bootstrap_probe legion_control_helper executable_snapshot_test helper_lifetime_test trusted_executable_test
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 legion-control-helper "$out/bin/legion-control-helper"
    install -Dm755 helper_bootstrap_probe "$out/bin/helper-bootstrap-probe"
    install -Dm755 executable_snapshot_test "$out/bin/executable-snapshot-test"
    install -Dm755 helper_lifetime_test "$out/bin/helper-lifetime-test"
    install -Dm755 trusted_executable_test "$out/bin/trusted-executable-test"
    runHook postInstall
  '';
}
