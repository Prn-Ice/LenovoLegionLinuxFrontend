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
      staticHelper = pkgs.pkgsStatic.callPackage ./packaging/nix/static-helper.nix { };
      appimage = pkgs.callPackage ./packaging/nix/appimage.nix { inherit frontend staticHelper; };
      frontendSource = pkgs.callPackage ./packaging/nix/sources.nix { inherit frontend; };
      tag = pkgs.writeShellApplication {
        name = "legion-tag";
        runtimeInputs = with pkgs; [
          bash
          coreutils
          git
          gnused
          jq
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
        inherit frontend appimage;
        frontend-source = frontendSource;
      };
      nixosModules.default =
        { pkgs, ... }:
        {
          environment.systemPackages = [ frontend ];
          systemd.services.legion-graphics = {
            description = "Apply Lenovo iGPU-only graphics before sign-in";
            after = [ "systemd-modules-load.service" "systemd-udev-trigger.service" ];
            before = [ "display-manager.service" ];
            wantedBy = [ "display-manager.service" ];
            path = [ pkgs.lsof ];
            restartIfChanged = false;
            unitConfig.ConditionPathExists = "/sys/devices/platform/legion/igpumode";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecCondition = "${pkgs.runtimeShell} -c '/run/current-system/sw/bin/legion_cli graphics-mode apply --help >/dev/null 2>&1'";
              ExecStart = "/run/current-system/sw/bin/legion_cli graphics-mode apply";
              TimeoutStartSec = "90s";
            };
          };
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
                yq-go
                jq
              ];
            }
            ''
              bash ${./test/tool/tag_test.sh} ${./tool/update_nix_metadata.sh} ${pkgs.lib.getExe tag}
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
        appimage-package =
          pkgs.runCommand "legion-appimage-check"
            {
              nativeBuildInputs = [ pkgs.patchelf ];
            }
            ''
              ${appimage} --appimage-extract >/dev/null
              test -x squashfs-root/AppRun
              test -x squashfs-root/usr/lib/legion_frontend/legion_frontend
              test -f squashfs-root/usr/share/glib-2.0/schemas/gschemas.compiled
              status=0
              while IFS= read -r -d "" file; do
                rpath="$(patchelf --print-rpath "$file" 2>/dev/null)" || continue
                case "$rpath" in
                  *nix/store*)
                    echo "The AppImage keeps a Nix store library path: $file" >&2
                    status=1
                    ;;
                esac
              done < <(find squashfs-root -type f -print0)
              [ "$status" = 0 ]
              touch "$out"
            '';
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
