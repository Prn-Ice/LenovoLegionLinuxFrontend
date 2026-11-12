FROM ubuntu:22.04@sha256:076e7bf82319619f28dd0aa9c02ab34b055ad37100395b4f49a2ffba04fb5e11

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git xz-utils unzip zip clang cmake ninja-build \
    pkg-config libgtk-3-dev libstdc++-12-dev libglib2.0-dev \
    libpolkit-gobject-1-dev openjdk-17-jdk-headless squashfs-tools \
    desktop-file-utils appstream python3 binutils dpkg-dev \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 1000 builder
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH=/opt/flutter/bin:${PATH}
USER builder
WORKDIR /home/builder/source
