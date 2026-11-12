{
  lib,
  stdenvNoCC,
  stdenv,
  appimageTools,
  patchelf,
  makeWrapper,
  coreutils,
  glibc,
  libglvnd,
  libx11,
  libxcb,
  wayland,
  image,
}:
let
  contents = appimageTools.extract {
    pname = "legion-appimage-contents";
    version = "1";
    src = image;
  };
  runtime = lib.makeLibraryPath [
    glibc
    stdenv.cc.cc.lib
    libglvnd
    libx11
    libxcb
    wayland
  ];
in
stdenvNoCC.mkDerivation {
  pname = "legion-appimage";
  version = "1";
  dontUnpack = true;
  nativeBuildInputs = [
    patchelf
    makeWrapper
  ];
  installPhase = ''
    mkdir -p "$out/app"
    cp -a ${contents}/. "$out/app/"
    chmod -R u+w "$out/app"
    bundle="$out/app/usr/lib/legion_frontend"
    for executable in "$bundle/legion_frontend" "$bundle/libexec/gdk-pixbuf-query-loaders"; do
      patchelf --set-interpreter ${stdenv.cc.bintools.dynamicLinker} "$executable"
    done
    # Keep every bundled library and the static helper byte-for-byte intact.
    makeWrapper "$out/app/AppRun" "$out/bin/legion-frontend" \
      --prefix LD_LIBRARY_PATH : ${lib.escapeShellArg "${runtime}:/run/opengl-driver/lib"} \
      --prefix PATH : ${lib.makeBinPath [ coreutils ]}
  '';
  dontFixup = true;
  meta.mainProgram = "legion-frontend";
}
