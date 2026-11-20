#!/usr/bin/env bash
# Select build, VM, and tooling checks from their changed inputs.
set -euo pipefail

base=''
head=HEAD
head_given=false
worktree=false
usage='Usage: bash tool/ci_build_changes.sh [--base COMMIT] [--head COMMIT | --worktree]'
while (($#)); do
  case "$1" in
    --base|--head)
      (($# >= 2)) || { echo "Missing value for $1" >&2; exit 2; }
      if [[ "$1" == --base ]]; then base=$2; else head=$2; head_given=true; fi
      shift 2
      ;;
    --worktree) worktree=true; shift ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
if [[ $worktree == true && $head_given == true ]]; then
  echo "$usage" >&2
  exit 2
fi

all=true
integration=true
lifecycle=true
nix=true
appimage=true
debian=true
tooling=true
if [[ -n "$base" ]]; then
  paths=$(mktemp)
  trap 'rm -f "$paths"' EXIT
  # Include both sides of renames, including code moved into documentation.
  if [[ $worktree == true ]]; then
    git diff --name-only --no-renames -z "$base" -- >"$paths"
    git ls-files --others --exclude-standard -z >>"$paths"
  else
    git diff --name-only --no-renames -z "$base" "$head" -- >"$paths"
  fi
  all=false
  integration=false
  lifecycle=false
  nix=false
  appimage=false
  debian=false
  tooling=false
  while IFS= read -r -d '' path; do
    case "$path" in
      .githooks/*|.github/*|tool/*|test/tool/*|test/support/*|test/fixtures/*|test/helpers/*|test/flutter_test_config.dart|flutter_test_config.dart|packaging/*|control/*|linux/*|flake.nix|flake.lock|pubspec.yaml|pubspec.lock|dart_test.yaml|analysis_options.yaml|LICENSE|THIRD_PARTY_NOTICES.md) tooling=true ;;
    esac
    case "$path" in
      .github/*|.metadata|pubspec.yaml|pubspec.lock) all=true ;;
      assets/*|lib/*|linux/*) integration=true; nix=true; appimage=true; debian=true ;;
      control/*) all=true ;;
      integration_test/*|tool/test_linux_journeys.sh) integration=true ;;
      flake.nix|flake.lock|packaging/nix/*) nix=true; lifecycle=true; appimage=true ;;
      packaging/debian/*|tool/build_deb.sh|tool/package_deb.dart|tool/fetch_debian_test_image.sh) debian=true ;;
      packaging/appimage/*) appimage=true; debian=true; nix=true ;;
      packaging/*) all=true ;;
      tool/package_linux.dart|tool/package_release.dart|tool/release_source/*|tool/packaging_files.dart|tool/bundle_notices.dart|tool/nix_flutter_provenance.dart|tool/test_portable_distro.sh|tool/portable_distro_*.sh|LICENSE|THIRD_PARTY_NOTICES.md) appimage=true; debian=true; nix=true ;;
      tool/*appimage*) appimage=true ;;
      tool/record_package_test_results.dart|tool/package_test_results.dart) appimage=true; debian=true ;;
      tool/update_nix_metadata.sh) nix=true ;;
      tool/ci_*|tool/release_workflow.dart|test/*|analysis_options.yaml) ;;
      tool/*) all=true ;;
    esac
  done <"$paths"
fi
if [[ $all == true ]]; then
  integration=true; lifecycle=true; nix=true; appimage=true; debian=true; tooling=true
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
emit tooling "$tooling"
