#!/usr/bin/env bash
# Link the approved helper into one ELF using the archived distro sources.
set -euo pipefail
if [[ $# != 4 ]]; then
  echo 'Usage: bash tool/build_static_helper.sh SOURCE_ROOT UTIL_LINUX_DSC BUILD_DIRECTORY OUTPUT' >&2
  exit 64
fi
root=$(realpath -- "$1")
dsc=$(realpath -- "$2")
build=$(realpath -m -- "$3")
output=$(realpath -m -- "$4")
mkdir -p "$build"
dpkg-source -x "$dsc" "$build/util-linux"
cd "$build/util-linux"
autoreconf -fi
./configure --disable-all-programs --enable-libmount --enable-libblkid \
  --enable-static --disable-shared --without-selinux --without-udev
make -j2 libmount.la libblkid.la
cmake -S "$root/telemetry" -B "$build/helper" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=g++-12 \
  -DBUILD_TESTING=OFF -DBUILD_LEGION_CONTROL_SERVICE=OFF \
  -DBUILD_PORTABLE_CONTROL_HELPER=ON -DBUILD_PORTABLE_CONTROL_STATIC=ON \
  -DCMAKE_LIBRARY_PATH="$build/util-linux/.libs"
cmake --build "$build/helper" --parallel 2 --target legion_portable_control
install -m755 "$build/helper/legion-portable-control" "$output"
strip --strip-debug "$output"
if readelf -lW -dW "$output" | grep -E 'INTERP|NEEDED|RPATH|RUNPATH'; then
  echo 'The AppImage helper must have no dynamic loader or shared libraries.' >&2
  exit 1
fi
