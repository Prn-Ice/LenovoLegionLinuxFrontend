{
  stdenv,
  lib,
  cmake,
  pkg-config,
  glib,
}:

stdenv.mkDerivation {
  pname = "legion-control-vm-fixtures";
  version = "1";
  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ./CMakeLists.txt
      ./test_vm_guard.h
      ./control_lifecycle_fixture.cc
      ./control_lifecycle_client.cc
      ./portable_control_client.cc
      ../portable_peer.cc
      ../portable_peer.h
    ];
  };
  nativeBuildInputs = [
    cmake
    pkg-config
  ];
  buildInputs = [ glib ];
  preConfigure = "cd control/test";
}
