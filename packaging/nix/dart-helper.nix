{ pkgs, dart, packageConfig }:

let
  source = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ../../control/dart
      ../../tool/build_dart_helper_bundle.dart
      ../../pubspec.yaml
      ../../pubspec.lock
    ];
  };
in
pkgs.runCommand "legion-dart-control-bundle"
  {
    nativeBuildInputs = [
      dart
      pkgs.binutils
      pkgs.pkg-config
      pkgs.patchelf
      pkgs.jq
    ];
    buildInputs = [ pkgs.systemd ];
  }
  ''
    export HOME="$TMPDIR"
    cp -r ${source} source
    chmod -R u+w source
    cd source
    mkdir -p .dart_tool
    jq --arg root "file://$PWD/" \
      '(.packages[] | select(.name == "legion_frontend")) |=
        (.rootUri = $root | .languageVersion = "3.14")' \
      ${packageConfig} > .dart_tool/package_config.json
    dart tool/build_dart_helper_bundle.dart \
      --sdk ${dart} --root "$PWD" \
      --source "$PWD/control/dart/run_control_helper.dart" \
      --output "$out" --objcopy objcopy --linker ld \
      --patchelf patchelf --pkg-config pkg-config --ldd ldd
  ''
