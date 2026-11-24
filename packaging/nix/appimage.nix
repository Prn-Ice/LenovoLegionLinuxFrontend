{
  lib,
  stdenv,
  fetchurl,
  patchelf,
  binutils,
  squashfsTools,
  glib,
  gdk-pixbuf,
  gtk3,
  dconf,
  gsettings-desktop-schemas,
  adwaita-icon-theme,
  dejavu_fonts,
  xdg-user-dirs,
  frontend,
}:

let
  specification = lib.importJSON ../../packaging/appimage/build-inputs.json;
  runtime = fetchurl {
    url = specification.runtime.url;
    sha256 = specification.runtime.sha256;
  };
  applicationId = "io.github.prnice.legion_linux_frontend";
  iconName = "legion_frontend";

  # Loader, C library, and graphics interfaces come from the host so its
  # display server and driver stack match the bundled desktop libraries.
  hostLibraries = [
    "ld-linux-x86-64.so.2"
    "libc.so.6"
    "libm.so.6"
    "libmvec.so.1"
    "libdl.so.2"
    "libpthread.so.0"
    "librt.so.1"
    "libresolv.so.2"
    "libutil.so.1"
    "libGL.so.1"
    "libEGL.so.1"
    "libGLESv2.so.2"
    "libGLdispatch.so.0"
    "libGLX.so.0"
    "libOpenGL.so.0"
    "libglapi.so.0"
    "libdrm.so.2"
    "libgbm.so.1"
  ];
in
stdenv.mkDerivation {
  name = "legion-frontend-${frontend.version}-x86_64.AppImage";
  dontUnpack = true;
  # The output is the finished image; rewriting it would corrupt the payload.
  dontStrip = true;
  dontPatchELF = true;
  dontPatchShebangs = true;
  nativeBuildInputs = [
    patchelf
    binutils
    squashfsTools
    glib
    (lib.getDev glib)
    (lib.getDev gdk-pixbuf)
  ];

  buildPhase = ''
    runHook preBuild

    appdir="$PWD/appdir"
    bundle="$appdir/usr/lib/legion_frontend"
    mkdir -p "$appdir/usr/bin" "$appdir/usr/etc/fonts" \
      "$appdir/usr/share/glib-2.0/schemas" "$appdir/usr/share/icons" \
      "$appdir/usr/share/fonts" \
      "$bundle/lib/gio/modules" "$bundle/lib/pixbuf-loaders" "$bundle/libexec"
    cp -r ${frontend}/app/legion-linux-frontend/. "$bundle/"
    cp -L ${xdg-user-dirs}/bin/xdg-user-dir "$appdir/usr/bin/"

    # Runtime data that the Nix package leaves to the host system.
    cp -L ${lib.getDev gdk-pixbuf}/bin/gdk-pixbuf-query-loaders "$bundle/libexec/"
    cp -L ${gdk-pixbuf}/lib/gdk-pixbuf-2.0/*/loaders/*.so "$bundle/lib/pixbuf-loaders/"
    cp -L ${lib.getLib dconf}/lib/gio/modules/libdconfsettings.so \
      "$bundle/lib/gio/modules/"
    cp ${gsettings-desktop-schemas}/share/gsettings-schemas/*/glib-2.0/schemas/*.xml \
      "$appdir/usr/share/glib-2.0/schemas/"
    cp ${gtk3}/share/gsettings-schemas/*/glib-2.0/schemas/*.xml \
      "$appdir/usr/share/glib-2.0/schemas/"
    cp -rL ${adwaita-icon-theme}/share/icons/. "$appdir/usr/share/icons/"
    cp -r ${dejavu_fonts}/share/fonts/. "$appdir/usr/share/fonts/"
    chmod -R u+w "$appdir"

    isElf() {
      [ "$(od -An -tx1 -N4 "$1" | tr -d ' \n')" = 7f454c46 ]
    }

    # Copy the transitive library closure beside the app so the image does not
    # depend on Nix store paths.
    queue="$TMPDIR/elf-queue"
    find "$bundle" "$appdir/usr/bin" -type f > "$queue"
    while [ -s "$queue" ]; do
      next="$TMPDIR/elf-next"
      : > "$next"
      while IFS= read -r file; do
        isElf "$file" || continue
        ldd "$file" > "$TMPDIR/ldd" 2>/dev/null || true
        while read -r name arrow path _; do
          [ "$arrow" = "=>" ] || continue
          base="$(basename "$name")"
          case " ${lib.concatStringsSep " " hostLibraries} " in
            *" $base "*) continue ;;
          esac
          if [ "$path" = not ]; then
            echo "Unresolved dependency $name for $file" >&2
            exit 1
          fi
          if [ ! -e "$bundle/lib/$base" ]; then
            cp -L "$path" "$bundle/lib/$base"
            chmod u+w "$bundle/lib/$base"
            echo "$bundle/lib/$base" >> "$next"
          fi
        done < "$TMPDIR/ldd"
      done < "$queue"
      mv "$next" "$queue"
    done

    # Point every copied ELF at its neighbours instead of the Nix store.
    find "$bundle" "$appdir/usr/bin" -type f -print0 |
      while IFS= read -r -d "" file; do
        isElf "$file" || continue
        case "$file" in
          "$bundle"/lib/pixbuf-loaders/*) rpath='$ORIGIN/..' ;;
          "$bundle"/lib/*) rpath='$ORIGIN' ;;
          "$bundle"/libexec/*) rpath='$ORIGIN/../lib' ;;
          "$appdir"/usr/bin/*) rpath='$ORIGIN/../../lib/legion_frontend/lib' ;;
          *) rpath='$ORIGIN/lib' ;;
        esac
        patchelf --set-rpath "$rpath" "$file"
        if readelf -lW "$file" | grep -q "Requesting program interpreter"; then
          patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 "$file"
        fi
      done

    ${lib.getDev glib}/bin/gio-querymodules "$bundle/lib/gio/modules"
    ${lib.getDev glib}/bin/glib-compile-schemas "$appdir/usr/share/glib-2.0/schemas"

    cat > "$appdir/usr/etc/fonts/fonts.conf" <<EOF
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <dir>usr/share/fonts</dir>
      <dir>/usr/share/fonts</dir>
      <dir>/usr/local/share/fonts</dir>
      <dir prefix="xdg">fonts</dir>
      <cachedir prefix="xdg">fontconfig</cachedir>
    </fontconfig>
    EOF

    install -m755 ${../../packaging/appimage/AppRun} "$appdir/AppRun"
    sed "s|^Icon=${applicationId}$|Icon=${iconName}|" \
      ${../../packaging/appimage/${applicationId}.desktop} \
      > "$appdir/${applicationId}.desktop"
    cp ${../../assets/branding/legion_app.svg} "$appdir/${iconName}.svg"
    cp ${../../assets/branding/legion_app.png} "$appdir/${iconName}.png"
    ln -s "${iconName}.png" "$appdir/.DirIcon"
    mkdir -p "$appdir/usr/share/doc/legion-frontend"
    cat > "$appdir/usr/share/doc/legion-frontend/appimage.txt" <<EOF
    Local Nix build of the Lenovo Legion Linux frontend AppImage.
    It bundles the desktop libraries from the flake's Nixpkgs instead of Ubuntu 22.04 and has no source companion.
    EOF

    mksquashfs "$appdir" "$TMPDIR/payload.squashfs" \
      -noappend -root-owned -comp zstd -Xcompression-level 19 -no-progress

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cat ${runtime} "$TMPDIR/payload.squashfs" > "$out"
    chmod 755 "$out"
    runHook postInstall
  '';

  meta = {
    description = "Local AppImage of the Lenovo Legion Linux frontend, built without a container";
    homepage = "https://github.com/Prn-Ice/LenovoLegionLinuxFrontend";
    license = lib.licenses.gpl2Plus;
    platforms = [ "x86_64-linux" ];
  };
}
