{
  lib,
  flutterSdk,
  flutter,
  cmake,
  ninja,
  patchelf,
  autoPatchelfHook,
  gtk3,
  glib,
  polkit,
  libthai,
  fribidi,
  libglvnd,
  jdk17,
  jq,
}:

let
  pubspec = lib.importJSON ./pubspec.json;
  applicationId = "io.github.prnice.legion_linux_frontend";
in
(flutterSdk.buildFlutterApplication.override { inherit flutter; }) {
  pname = "legion-linux-frontend";
  version = pubspec.version;
  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../lib
      ../../assets
      ../../linux
      ../../control
      ../../telemetry
      ../../packaging
      ../../tool
      ../../pubspec.yaml
      ../../pubspec.lock
      ../../LICENSE
      ../../THIRD_PARTY_NOTICES.md
      ../../flake.nix
      ../../flake.lock
      ../../README.md
      ../../CONTRIBUTING.md
      ../../docs
    ];
  };
  pubspecLock = lib.importJSON ./pubspec.lock.json;
  nativeBuildInputs = [
    cmake
    ninja
    patchelf
    autoPatchelfHook
    jq
  ];
  buildInputs = [
    gtk3
    glib
    polkit
    libthai
    fribidi
    jdk17
  ];
  runtimeDependencies = [ libglvnd ];
  dontUseCmakeConfigure = true;
  JAVA_HOME = "${jdk17}";
  NIX_CFLAGS_COMPILE = "-I${lib.getDev fribidi}/include/fribidi";

  preBuild = ''
    # Pub2nix supplies immutable package roots. Link Linux plugins without
    # running pub again or replacing that resolved package configuration.
    mkdir -p linux/flutter/ephemeral/.plugin_symlinks
    while IFS=$'\t' read -r name root; do
      if [ -d "$root/linux" ]; then
        ln -s "$root" "linux/flutter/ephemeral/.plugin_symlinks/$name"
      fi
    done < <(jq -r '.packages[] | [.name, (.rootUri | sub("^file://"; ""))] | @tsv' \
      .dart_tool/package_config.json)

    # pub2nix uses the lock's SDK floor for the root package. Preserve the
    # source language version declared by this project's pubspec instead.
    ${lib.getExe jq} --arg name ${lib.escapeShellArg pubspec.name} \
      --arg language ${lib.escapeShellArg (lib.versions.majorMinor (lib.removePrefix "^" pubspec.environment.sdk))} \
      '(.packages[] | select(.name == $name) | .languageVersion) = $language' \
      .dart_tool/package_config.json > .dart_tool/package_config.updated.json
    mv .dart_tool/package_config.updated.json .dart_tool/package_config.json
  '';
  buildPhase = ''
    runHook preBuild
    flutter build linux --release --no-pub --config-only --split-debug-info="$debug" \
      --dart-define=LLLF_ENABLE_PORTABLE_CONTROL=true
    cmake -S linux -B build/linux/x64/release \
      -DBUILD_LEGION_CONTROL_SERVICE=OFF -DBUILD_PORTABLE_CONTROL_HELPER=ON
    flutter build linux --release --no-pub --split-debug-info="$debug" \
      --dart-define=LLLF_ENABLE_PORTABLE_CONTROL=true
    runHook postBuild
  '';
  postInstall = ''
    bundle="$out/app/$pname"
    rm -rf "$bundle/lib/systemd" "$bundle/lib/sysusers.d" \
      "$bundle/share/dbus-1" "$bundle/share/polkit-1"
    rm -f "$bundle/libexec/legion-telemetry-service"
    install -Dm644 packaging/appimage/${applicationId}.desktop \
      "$out/share/applications/${applicationId}.desktop"
    install -Dm644 packaging/appimage/${applicationId}.metainfo.xml \
      "$out/share/metainfo/${applicationId}.metainfo.xml"
    install -Dm644 assets/branding/legion_mark.svg \
      "$out/share/icons/hicolor/scalable/apps/${applicationId}.svg"
    install -Dm644 assets/branding/README.md \
      "$bundle/share/licenses/legion_frontend/branding/README.md"
  '';
  preFixup = ''
    addAutoPatchelfSearchPath "${jdk17}/lib/server"
  '';
  meta = {
    description = "Lenovo Legion hardware frontend with temporary administrator access";
    homepage = "https://github.com/Prn-Ice/LenovoLegionLinuxFrontend";
    license = lib.licenses.gpl2Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "legion_frontend";
  };
}
