{
  lib,
  runCommand,
  writeText,
  gnutar,
  gzip,
  frontend,
}:

let
  lock = lib.importJSON ./pubspec.lock.json;
  hosted = lib.filterAttrs (_: package: package.source == "hosted") lock.packages;
  sources = frontend.pubspecLock.dependencySources;
  manifest = writeText "legion-source-manifest.json" (
    builtins.toJSON {
      version = frontend.version;
      projectSource = toString frontend.src;
      dependencies = lib.mapAttrs (name: package: {
        inherit (package) version description;
        source = toString sources.${name};
      }) hosted;
    }
  );
in
runCommand "legion-linux-frontend-${frontend.version}-source"
  {
    nativeBuildInputs = [
      gnutar
      gzip
    ];
  }
  ''
    mkdir -p source/project source/dependencies "$out"
    cp -R ${frontend.src}/. source/project/
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: _: ''
        cp -RL ${sources.${name}}/${sources.${name}.packageRoot} source/dependencies/${lib.escapeShellArg name}
      '') hosted
    )}
    cp ${manifest} source/manifest.json
    cat > source/README.txt <<'EOF'
    This archive contains the project and the hosted Dart package sources used
    by its Nix build. manifest.json records their immutable Nix source paths
    and pub.dev archive hashes. Each dependency retains its own license files.

    Build with: nix build ./project#frontend
    The first build downloads the pinned SDK, native dependencies, and package
    inputs. Once fetched, Nix builds the application in its offline sandbox.
    The flake and pubspec locks identify those inputs. Hosted source copies in
    dependencies/ are supplied for inspection and modification; the recipe
    resolves its inputs through the locks.
    EOF
    tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
      -C source -czf "$out/legion-linux-frontend-${frontend.version}-source.tar.gz" .
  ''
