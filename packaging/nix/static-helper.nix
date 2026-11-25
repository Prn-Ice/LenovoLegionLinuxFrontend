{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  glib,
  util-linux,
}:
stdenv.mkDerivation {
  pname = "legion-control-helper-static";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../..;
    fileset = ../../control;
  };
  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];
  buildInputs = [
    glib
    util-linux
  ];
  cmakeDir = "../control";
  cmakeFlags = [
    "-DBUILD_TESTING=OFF"
    "-DBUILD_CONTROL_HELPER=ON"
    "-DBUILD_CONTROL_STATIC=ON"
  ];
  buildFlags = [ "legion_control_helper" ];
  installPhase = ''
    runHook preInstall
    install -Dm755 legion-control-helper "$out/libexec/legion-control-helper"
    runHook postInstall
  '';
}
