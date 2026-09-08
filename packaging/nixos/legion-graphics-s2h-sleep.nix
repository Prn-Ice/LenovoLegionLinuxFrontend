{
  systemd,
  preflight,
  python3,
  buildPackages,
  lib,
  bash,
  bashNonInteractive,
}:

# Only systemd-suspend-then-hibernate.service consumes this package's sleep
# executable. Keep the host's systemd version, build options, and existing
# patches; do not replace PID 1 or reimplement systemd's timer/battery logic.
let
  # Keep unrelated frontend/documentation commits out of the systemd build key.
  patch = builtins.path {
    path = ./legion-graphics-s2h-preflight.patch;
    name = "legion-graphics-s2h-preflight.patch";
  };
  test = builtins.path {
    path = ../../tool/test_graphics_s2h_guard.py;
    name = "test_graphics_s2h_guard.py";
  };
in
systemd.overrideAttrs (previous: {
  pname = "legion-systemd-sleep";
  separateDebugInfo = false;
  patches = (previous.patches or [ ]) ++ [ patch ];
  postPatch = (previous.postPatch or "") + ''
    substituteInPlace src/sleep/sleep.c \
      --replace-fail '@legionHibernatePreflight@' '${preflight}'
    CC=${buildPackages.stdenv.cc}/bin/cc \
      ${python3}/bin/python3 ${test} src/sleep/sleep.c
  '';
  buildPhase = ''
    runHook preBuild
    ninja -j "$NIX_BUILD_CORES" systemd-sleep
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    for outputPath in "''${outputs[@]}"; do
      mkdir -p "$outputPath"
    done
    mkdir -p "$out/lib/systemd"
    cp systemd-sleep src/shared/libsystemd-shared-*.so "$out/lib/systemd/"
    patchelf --add-rpath "$out/lib/systemd" "$out/lib/systemd/systemd-sleep"
    runHook postInstall
  '';
  # The other upstream install hooks expect the full systemd/udev installation.
  postInstall = "";
  postFixup = "";
  installCheckPhase = ''
    "$out/lib/systemd/systemd-sleep" --help > /dev/null
  '';
  # The upstream package excludes shells; this sleep helper intentionally calls
  # the existing bounded shell preflight. Preserve any other exclusions.
  disallowedRequisites = lib.subtractLists [ bash bashNonInteractive ] (
    previous.disallowedRequisites or [ ]
  );
})
