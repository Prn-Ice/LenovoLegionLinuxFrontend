{
  stdenv,
  lib,
  cmake,
  pkg-config,
  glib,
  polkit,
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
  buildInputs = [ glib polkit ];

  preConfigure = ''
    cd telemetry
  '';
  cmakeFlags = [
    "-DBUILD_TESTING=ON"
    "-DBUILD_LEGION_CONTROL_SERVICE=ON"
  ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    cmake --build . --target legion_telemetry_service legion_control_service package_power_sampler_test control_commands_test
    ctest --output-on-failure
    runHook postCheck
  '';

  meta = {
    description = "Lenovo Legion telemetry and privileged hardware control services";
    platforms = lib.platforms.linux;
    mainProgram = "legion-telemetry-service";
  };
}
