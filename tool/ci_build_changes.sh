#!/usr/bin/env bash
# Select expensive checks from their app, native, and packaging inputs.
set -euo pipefail

base=''
head=HEAD
while (($#)); do
  case "$1" in
    --base|--head)
      (($# >= 2)) || { echo "Missing value for $1" >&2; exit 2; }
      if [[ "$1" == --base ]]; then base=$2; else head=$2; fi
      shift 2
      ;;
    *) echo "Usage: bash tool/ci_build_changes.sh [--base COMMIT] [--head COMMIT]" >&2; exit 2 ;;
  esac
done

all=true
integration=true
lifecycle=true
nix=true
appimage=true
debian=true
if [[ -n "$base" ]]; then
  paths=$(mktemp)
  trap 'rm -f "$paths"' EXIT
  # Include both sides of renames, including code moved into documentation.
  git diff --name-only --no-renames -z "$base" "$head" -- >"$paths"
  all=false
  integration=false
  lifecycle=false
  nix=false
  appimage=false
  debian=false
  while IFS= read -r -d '' path; do
    case "$path" in
      .github/*|.metadata|pubspec.yaml|pubspec.lock) all=true ;;
      assets/*|lib/*|linux/*) integration=true; nix=true; appimage=true; debian=true ;;
      control/*|telemetry/*) all=true ;;
      integration_test/*|tool/test_linux_journeys.sh) integration=true ;;
      flake.nix|flake.lock|packaging/nix/*) nix=true; lifecycle=true; appimage=true ;;
      packaging/debian/*|tool/build_deb.sh|tool/package_deb.dart|tool/fetch_debian_test_image.sh) debian=true ;;
      packaging/appimage/*) appimage=true; debian=true; nix=true ;;
      packaging/*) all=true ;;
      tool/package_linux.dart|tool/package_release.dart|tool/packaging_files.dart|tool/bundle_notices.dart|tool/nix_flutter_provenance.dart|tool/test_portable_distro.sh|tool/portable_distro_*.sh|LICENSE|THIRD_PARTY_NOTICES.md) appimage=true; debian=true; nix=true ;;
      tool/*appimage*) appimage=true ;;
      tool/update_nix_metadata.sh) nix=true ;;
      tool/ci_*|tool/release_workflow.dart|tool/find_release_ci.dart|test/*|analysis_options.yaml) ;;
      tool/*) all=true ;;
    esac
  done <"$paths"
fi
if [[ $all == true ]]; then
  integration=true; lifecycle=true; nix=true; appimage=true; debian=true
fi
emit() {
  printf '%s=%s\n' "$1" "$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
  fi
}
emit integration "$integration"
emit lifecycle "$lifecycle"
emit nix "$nix"
emit appimage "$appimage"
emit debian "$debian"
