{
  stdenv,
  lib,
  cmake,
  pkg-config,
  glib,
  polkit,
  dbus,
}:

stdenv.mkDerivation {
  pname = "legion-telemetry-and-control-services";
  version = "1.0.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../telemetry
      ../control
      ../packaging
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

  preConfigure = ''
    cd telemetry
  '';
  cmakeFlags = [
    "-DBUILD_TESTING=ON"
    "-DBUILD_LEGION_CONTROL_SERVICE=ON"
  ];

  doCheck = true;
  nativeCheckInputs = [ dbus ];
  checkPhase = ''
    runHook preCheck
    cmake --build . --target legion_telemetry_service legion_control_service graphics_next_boot package_power_sampler_test control_commands_test graphics_boot_service_test managed_command_test executable_snapshot_test portable_lifetime_test portable_peer_test trusted_executable_test portable_cli_test
    ctest --output-on-failure
    runHook postCheck
  '';

  meta = {
    description = "Lenovo Legion telemetry and privileged hardware control services";
    platforms = lib.platforms.linux;
    mainProgram = "legion-telemetry-service";
  };
}
