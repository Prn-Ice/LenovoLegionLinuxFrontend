let
  project = builtins.getFlake (toString ../..);
  pkgs = import project.inputs.nixpkgs { system = builtins.currentSystem; };
  # The upstream SDK's engine needs these shared libraries outside /usr/lib.
  libraries = with pkgs; [
    gtk3
    glib
    pango
    atk
    cairo
    libepoxy
    wayland
    fontconfig
    libGL
  ];
in
project.devShells.${builtins.currentSystem}.default.overrideAttrs (previous: {
  buildInputs = previous.buildInputs ++ libraries;
  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath libraries;
})
