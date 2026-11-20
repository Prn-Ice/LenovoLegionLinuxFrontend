{
  description = "Lenovo Legion Linux frontend and development tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      # SDK and tool dependency hashes come from the official stable release.
      flutterSdk = pkgs.flutterPackages.mkFlutter (
        builtins.fromJSON (builtins.readFile ./packaging/nix/flutter.json)
        // {
          # Adapt Nixpkgs' SDK tool patches to Flutter 3.50's moved methods.
          patches =
            builtins.filter (
              patch:
              !(builtins.elem (builtins.baseNameOf patch) [
                "disable-auto-update.patch"
                "override-host-platform-base.patch"
              ])
            ) pkgs.flutter.unwrapped.patches
            ++ [
              ./packaging/nix/flutter-tools.patch
            ];
        }
      );
      flutter = (pkgs.flutterPackages.wrapFlutter flutterSdk).override {
        supportedTargetFlutterPlatforms = [
          "universal"
          "linux"
        ];
        extraPkgConfigPackages = [ pkgs.libthai ];
      };
      frontend = pkgs.callPackage ./packaging/nix/frontend.nix { inherit flutterSdk flutter; };
      frontendSource = pkgs.callPackage ./packaging/nix/sources.nix { inherit frontend; };
      tag = pkgs.writeShellApplication {
        name = "legion-tag";
        runtimeInputs = with pkgs; [
          git
          yq-go
          openssh
          gnupg
        ];
        text = builtins.readFile ./tool/tag.sh;
      };
    in
    {
      packages.${system} = {
        default = frontend;
        inherit frontend;
        frontend-source = frontendSource;
      };
      apps.${system} = {
        default = {
          type = "app";
          program = pkgs.lib.getExe frontend;
        };
        frontend = {
          type = "app";
          program = pkgs.lib.getExe frontend;
        };
        tag = {
          type = "app";
          program = pkgs.lib.getExe tag;
        };
      };
      checks.${system} = {
        release-tag =
          pkgs.runCommand "legion-tag-test"
            {
              nativeBuildInputs = with pkgs; [
                git
                openssh
              ];
            }
            ''
              bash ${./test/tool/tag_test.sh} ${pkgs.lib.getExe tag}
              touch "$out"
            '';
        frontend-package = import ./control/test/frontend_package.nix { inherit pkgs frontend; };
        nix-metadata =
          pkgs.runCommand "legion-nix-metadata"
            {
              nativeBuildInputs = [
                pkgs.yq-go
                pkgs.jq
                pkgs.diffutils
              ];
            }
            ''
              yq -o=json '.' ${./pubspec.yaml} | jq -S . > pubspec.json
              yq -o=json '.' ${./pubspec.lock} | jq -S . > pubspec.lock.json
              diff -u ${./packaging/nix/pubspec.json} pubspec.json
              diff -u ${./packaging/nix/pubspec.lock.json} pubspec.lock.json
              touch "$out"
            '';
        helper-bootstrap = import ./control/test/helper_bootstrap.nix {
          inherit pkgs;
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          flutter
          clang
          cmake
          ninja
          pkg-config
          # Release fixtures inspect Debian and AppImage payloads.
          dpkg
          squashfsTools
          git
          openssh
          nix.out
          gtk3
          glib
          libthai
          fribidi
          gsettings-desktop-schemas
          jdk17
          dbus
          xvfb-run
          yq-go
          jq
        ];

        # JNI build hooks compile against this JDK and load its JVM at runtime.
        JAVA_HOME = "${pkgs.jdk17}";
        # Direct Dart commands need the Flutter root in Nix's split SDK layout.
        FLUTTER_ROOT = "${flutter}";
        LD_LIBRARY_PATH = "${pkgs.jdk17}/lib/server";
        # handy_window's bundled libhandy includes fribidi headers directly.
        NIX_CFLAGS_COMPILE = "-I${pkgs.lib.getDev pkgs.fribidi}/include/fribidi";
        GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
