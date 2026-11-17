#!/usr/bin/env bash
# Select packaging and VM checks for changed build inputs.
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

build=true
if [[ -n "$base" ]]; then
  paths=$(mktemp)
  trap 'rm -f "$paths"' EXIT
  # Include both sides of renames, including code moved into documentation.
  git diff --name-only --no-renames -z "$base" "$head" -- >"$paths"
  build=false
  while IFS= read -r -d '' path; do
    case "$path" in
      .github/*|assets/*|control/*|integration_test/*|lib/*|linux/*|packaging/*|telemetry/*|test/*|tool/*|.metadata|analysis_options.yaml|flake.nix|flake.lock|pubspec.yaml|pubspec.lock|LICENSE|THIRD_PARTY_NOTICES.md)
        build=true
        break
        ;;
    esac
  done <"$paths"
fi
printf 'build=%s\n' "$build"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'build=%s\n' "$build" >>"$GITHUB_OUTPUT"
fi
