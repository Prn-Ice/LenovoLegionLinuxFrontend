{
  description = "Lenovo Legion Linux frontend and development tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      # These source/artifact hashes and tool versions reproduce our working
      # Flutter 3.47.9 SDK while the pinned Nixpkgs still ships 3.47.4.
      base = builtins.fromJSON (
        builtins.readFile "${nixpkgs}/pkgs/development/compilers/flutter/versions/3_47/data.json"
      );
      flutterSdk = pkgs.flutterPackages.mkFlutter (
        base
        // {
          version = "3.47.9";
          engineVersion = "89c39edfdfae2949f6806e4a315c0c08522238b7";
          dartVersion = "3.13.7";
          flutterHash = "sha256-JBauGMdb1lmply2yAekkeonIX7+duVFixiHEREg+EG8=";
          dartHash.x86_64-linux = "sha256-65mu0mbvvLYVxq4hwS9Sz+k1ufIIvMxf6n9kwh6Gcik=";
          artifactHashes = {
            universal.x86_64-linux = "sha256-W0gnbSYZCHIHEVuL+AdOoAqcl4SJnFiB6AYQgjvk3s8=";
            linux.x86_64-linux = "sha256-Zv772L5KvosN3HVc8VSC6JF6+7b46QaKbETddtt6krg=";
          };
          patches = pkgs.flutter.unwrapped.patches;
          pubspecLock = base.pubspecLock // {
            packages = base.pubspecLock.packages // {
              dds = base.pubspecLock.packages.dds // {
                version = "5.4.0";
                description = base.pubspecLock.packages.dds.description // {
                  sha256 = "f8e875dcd7b5e5073a7bfe54095144c70487f18e2f8e47fa51c09dd67eccfb0c";
                };
              };
              devtools_shared = base.pubspecLock.packages.devtools_shared // {
                version = "13.1.0";
                description = base.pubspecLock.packages.devtools_shared.description // {
                  sha256 = "13df2c17d5f21dd7c92d08145386d45e1153364c04e531e994afb0ee7b67554b";
                };
              };
            };
          };
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
      appimageRunner = pkgs.writeShellApplication {
        name = "legion-appimage-run";
        runtimeInputs = [
          pkgs.nix
          pkgs.coreutils
          pkgs.python3
        ];
        runtimeEnv = {
          LLLF_APPIMAGE_NIXPKGS = "${nixpkgs}";
          LLLF_APPIMAGE_PACKAGING = "${./packaging/nix/appimage.nix}";
        };
        text = builtins.readFile ./tool/run_appimage_nixos.sh;
      };
      frontendSource = pkgs.callPackage ./packaging/nix/sources.nix { inherit frontend; };
    in
    {
      packages.${system} = {
        default = frontend;
        inherit frontend;
        appimage-run = appimageRunner;
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
        appimage-run = {
          type = "app";
          program = pkgs.lib.getExe appimageRunner;
        };
      };
      checks.${system} = {
        frontend-package = import ./control/test/frontend_package.nix { inherit pkgs frontend; };
        nix-metadata =
          pkgs.runCommand "legion-nix-metadata"
            {
              nativeBuildInputs = [
                pkgs.yq
                pkgs.diffutils
              ];
            }
            ''
              yq -S . ${./pubspec.yaml} > pubspec.json
              yq -S . ${./pubspec.lock} > pubspec.lock.json
              diff -u ${./packaging/nix/pubspec.json} pubspec.json
              diff -u ${./packaging/nix/pubspec.lock.json} pubspec.lock.json
              touch "$out"
            '';
        control-lifecycle = import ./control/test/control_lifecycle.nix {
          inherit pkgs;
        };
        portable-bootstrap = import ./control/test/portable_bootstrap.nix {
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
          git
          nix.out
          gtk3
          glib
          polkit
          libthai
          fribidi
          gsettings-desktop-schemas
          jdk17
          dbus
          xvfb-run
          yq
        ];

        # JNI build hooks compile against this JDK and load its JVM at runtime.
        JAVA_HOME = "${pkgs.jdk17}";
        LD_LIBRARY_PATH = "${pkgs.jdk17}/lib/server";
        # handy_window's bundled libhandy includes fribidi headers directly.
        NIX_CFLAGS_COMPILE = "-I${pkgs.lib.getDev pkgs.fribidi}/include/fribidi";
        GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
