{
  stdenv,
  lib,
  cmake,
  pkg-config,
  glib,
}:

stdenv.mkDerivation {
  pname = "legion-telemetry-service";
  version = "1.0.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../telemetry
      ../packaging
    ];
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];
  buildInputs = [ glib ];

  preConfigure = ''
    cd telemetry
  '';
  cmakeFlags = [ "-DBUILD_TESTING=ON" ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    cmake --build . --target package_power_sampler_test
    ctest --output-on-failure
    runHook postCheck
  '';

  meta = {
    description = "Read-only CPU package power telemetry for Legion Frontend";
    platforms = lib.platforms.linux;
    mainProgram = "legion-telemetry-service";
  };
}
