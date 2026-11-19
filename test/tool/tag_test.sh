#!/usr/bin/env bash
# Exercise the tag app with a disposable signing key and local remote.
set -euo pipefail
app=("$@")
# A hook's repository pointers must not reach either fixture repository.
for name in ${!GIT_@}; do unset "$name"; done
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export HOME="$temporary/home" XDG_CONFIG_HOME="$temporary/config"
export GIT_TEMPLATE_DIR="$temporary/empty"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$GIT_TEMPLATE_DIR"
ssh-keygen -q -t ed25519 -N '' -f "$temporary/key"
printf 'test@example.invalid %s\n' "$(cat "$temporary/key.pub")" > "$temporary/signers"
git init -q --bare "$temporary/remote"
git init -q "$temporary/repo"
cd "$temporary/repo"
git config user.name 'Tag test'
git config user.email test@example.invalid
git config gpg.format ssh
git config user.signingKey "$temporary/key"
git config gpg.ssh.allowedSignersFile "$temporary/signers"
git config commit.gpgSign true
git remote add origin "$temporary/remote"

expect_failure() {
  if "${app[@]}" "$@" > "$temporary/failure.log" 2>&1; then
    echo "Expected failure: $*" >&2
    exit 1
  fi
}

printf 'version: "0.1.0-alpha.2+1"\n' > pubspec.yaml
git add pubspec.yaml
git commit -qm 'Set alpha version'
"${app[@]}" --help
expect_failure --unknown
expect_failure --push --help
"${app[@]}"
tag=refs/tags/v0.1.0-alpha.2
original=$(git rev-parse "$tag")
git verify-tag "$tag"
test "$(git rev-parse "$tag^{commit}")" = "$(git rev-parse HEAD)"
test -z "$(git --git-dir="$temporary/remote" show-ref)"

# Verification failures must stop before pushing.
git config gpg.ssh.allowedSignersFile "$temporary/missing"
expect_failure --push
test -z "$(git --git-dir="$temporary/remote" show-ref)"
git config gpg.ssh.allowedSignersFile "$temporary/signers"

# Retrying preserves the signed object and pushes only the requested tag.
git tag -s unrelated -m unrelated
git config push.followTags true
"${app[@]}" --push
test "$(git rev-parse "$tag")" = "$original"
test "$(git --git-dir="$temporary/remote" show-ref)" = "$original $tag"

echo '# dirty' >> pubspec.yaml
expect_failure
git restore pubspec.yaml
touch untracked
expect_failure
rm untracked
git commit --allow-empty -qm 'Move HEAD'
expect_failure --push
test "$(git rev-parse "$tag")" = "$original"

printf 'version: invalid\n' > pubspec.yaml
git commit -qam 'Set invalid version'
expect_failure
printf 'version: 1.2.3+4\n' > pubspec.yaml
git commit -qam 'Set stable version'
git tag v1.2.3
expect_failure --push
git tag -d v1.2.3
git config user.signingKey "$temporary/missing"
expect_failure --push
test -z "$(git tag --list v1.2.3)"
git config user.signingKey "$temporary/key"

# A rejected push keeps the local signed tag for a later retry.
git --git-dir="$temporary/remote" tag v1.2.3 "$original^{commit}"
expect_failure --push
git verify-tag v1.2.3
test "$(git --git-dir="$temporary/remote" rev-parse refs/tags/v1.2.3)" = \
  "$(git rev-parse "$original^{commit}")"
git --git-dir="$temporary/remote" tag -d v1.2.3
"${app[@]}" --push
test "$(git --git-dir="$temporary/remote" rev-parse refs/tags/v1.2.3)" = \
  "$(git rev-parse refs/tags/v1.2.3)"
echo 'Tag app checks passed.'
