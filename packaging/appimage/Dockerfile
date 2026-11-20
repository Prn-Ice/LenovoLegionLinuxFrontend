FROM ubuntu:22.04@sha256:076e7bf82319619f28dd0aa9c02ab34b055ad37100395b4f49a2ffba04fb5e11

ENV DEBIAN_FRONTEND=noninteractive
# Keep verified packages and indexes if an install fails halfway through.
# Copy signed indexes into the image for source-package lookups after the build.
RUN --mount=type=cache,id=legion-jammy-archives,target=/var/cache/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Dir::State::lists "/var/cache/apt/lists";' >/etc/apt/apt.conf.d/99build-cache \
    && mkdir -p /var/cache/apt/lists/partial \
    && apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git xz-utils unzip zip clang cmake ninja-build \
    pkg-config libgtk-3-dev libstdc++-12-dev libglib2.0-dev \
    openjdk-17-jdk-headless squashfs-tools \
    desktop-file-utils appstream jq binutils dpkg-dev g++-12 \
    autoconf automake libtool gettext autopoint bison flex gtk-doc-tools \
    gsettings-desktop-schemas fonts-dejavu-core adwaita-icon-theme xdg-user-dirs \
    libgdk-pixbuf2.0-bin dconf-gsettings-backend \
    && sed -i 's/^# deb-src /deb-src /' /etc/apt/sources.list \
    && apt-get update \
    && cp -a /var/cache/apt/lists/. /var/lib/apt/lists/ \
    && rm /etc/apt/apt.conf.d/99build-cache
RUN useradd -m -u 1000 builder
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH=/opt/flutter/bin:${PATH}
USER builder
WORKDIR /home/builder/source
