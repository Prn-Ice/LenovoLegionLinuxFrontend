{
  stdenv,
  lib,
  cmake,
  pkg-config,
  glib,
  polkit,
  fixtures,
}:

stdenv.mkDerivation {
  pname = "legion-portable-bootstrap-probe";
  version = "1";
  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../control
      ../../telemetry
      ../../packaging
    ];
  };
  nativeBuildInputs = [
    cmake
    pkg-config
  ];
  buildInputs = [
    glib
    polkit
  ];
  preConfigure = "cd telemetry";
  cmakeFlags = [
    "-DBUILD_TESTING=ON"
    "-DBUILD_LEGION_CONTROL_SERVICE=ON"
    "-DBUILD_PORTABLE_BOOTSTRAP_PROTOTYPE=ON"
    "-DPORTABLE_CONTROL_TEST_CLI=${fixtures}/bin/legion_cli"
  ];
  buildPhase = ''
    runHook preBuild
    cmake --build . --target portable_bootstrap_probe executable_snapshot_test portable_lifetime_test
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 portable_bootstrap_probe "$out/bin/portable-bootstrap-probe"
    install -Dm755 executable_snapshot_test "$out/bin/executable-snapshot-test"
    install -Dm755 portable_lifetime_test "$out/bin/portable-lifetime-test"
    runHook postInstall
  '';
}
