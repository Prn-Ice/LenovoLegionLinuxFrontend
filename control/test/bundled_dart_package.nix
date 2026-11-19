{
  stdenv,
  lib,
  cmake,
  pkg-config,
  glib,
  bundle,
}:

stdenv.mkDerivation {
  pname = "legion-bundled-dart-prototype";
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
  buildInputs = [ glib ];
  preConfigure = "cd telemetry";
  cmakeFlags = [
    "-DBUILD_TESTING=ON"
    "-DBUILD_BUNDLED_DART_PROTOTYPE=ON"
    "-DBUILD_PORTABLE_CONTROL_STATIC=ON"
    "-DBUNDLED_DART_DIRECTORY=${bundle}"
  ];
  buildPhase = ''
    runHook preBuild
    cmake --build . --parallel 2 --target bundled_dart_bootstrap_probe bundled_dart_runtime_test
    runHook postBuild
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ctest --output-on-failure -R '^bundled_dart_runtime$'
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 bundled_dart_bootstrap_probe "$out/bin/bundled-dart-bootstrap-probe"
    if readelf -lW -dW "$out/bin/bundled-dart-bootstrap-probe" | grep -E 'INTERP|NEEDED|RPATH|RUNPATH'; then
      echo 'The prototype starter must include its libraries.' >&2
      exit 1
    fi
    runHook postInstall
  '';
  # The snapshot uses file offsets; post-build ELF rewriting is unnecessary.
  dontStrip = true;
  dontPatchELF = true;
}
