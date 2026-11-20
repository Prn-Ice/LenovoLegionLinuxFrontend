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
      ./control_cli_fixture.cc
      ../test_support/cli_help_fixture.h
      ./control_test_client.cc
      ../control_peer.cc
      ../control_peer.h
      ../helper_unit.h
      ../trusted_executable.cc
      ../trusted_executable.h
      ../trusted_executable_test.cc
    ];
  };
  nativeBuildInputs = [
    cmake
    pkg-config
  ];
  buildInputs = [ glib ];
  preConfigure = "cd control/test";
}
