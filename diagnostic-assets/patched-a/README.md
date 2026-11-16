# Temporary experimental A inputs

These existing artifacts are staged only for one hosted diagnostic, not a
release, download recommendation, or production dependency. This branch must
never be merged or tagged. Its normal branches and convenience artifacts remain
unchanged. The diagnostic PR will close after evidence collection; its branch
retains the staging history for audit. Hosted diagnostic artifacts expire after
seven days.

The source companion exceeded GitHub's 100 MiB per-file limit, so standard
`split -b 64M -d` produced two parts. Concatenation restores the original bytes;
the workflow verifies the original SHA256 before starting a guest. No package
or engine rebuild was performed.

- A package source: `61367a98775765d1144f2d9bd50a1a124a1ce7df`
- Package SHA256: `58cdf3943cc5b5650186cd484f7a918918f78af7781a5e2e4ba575422f5d4f43`
- Source SHA256: `eac236abd2fa6eaae4780a8963768218438fce6e57aed780569bbdb6fcc19c64`
- Patched engine/framework: `2ec26c4fc6b078d957242eb6c688ebc7526c7b9c`
- Runtime SHA256: `226a06ff64e17e4cc2468af63be9f2b737fddd680a8ae34e7e5c7c026bb506ad`
- Runtime build ID: `50fc1e9aa3a2f684cc9837bdfad045a735589fbe`

SDK version output is not custom-runtime provenance. The package manifest and
source companion retain the full experimental provenance and native-test
limitations. App retention is unchanged from `77a189e`.
