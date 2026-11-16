# Official Flutter 3.50 Debian 12 qualification

## Result

The exact official package from CI `43726942646` passed the missing Debian 12
qualification in a local disposable KVM guest. This is new platform coverage,
not a retry of the failed Ubuntu phase. No app or package was rebuilt.

- Dashboard rendered after 1.9 seconds.
- The single ordinary normal close exited zero. No 20-close loop ran.
- Installation/payload verification, helper approval, denial, missing agent,
  readback/restoration, upgrade, purge, and existing-integration preservation
  all passed.
- Qualification, collection, and archive statuses were zero.
- Before app launch, the approved-user controlled abort proved unlimited soft
  and hard core limits, retained its raw SIGABRT core, and produced a GDB
  backtrace and mappings. Both GDB status fields were zero.
- No app failure/core occurred. The only core was the controlled fixture.

The original Ubuntu 22.04 normal-close failure remains unresolved. This local
Debian 12 result does not turn the failed CI run green or establish a shutdown
fix. The user-reported working official AppImage and authentication retry are
separate evidence; real-hardware readback/restoration remain unreported here.

## Exact official inputs

- Package SHA256: `3b169c4d1fe8cb684c958363ded0a43b399b1dfed226e390ef023af06a85bae2`
- Source SHA256: `321ec05b544d4977d0634fbcd088873d7a5669f07d5561fe6c3ed60686145162`
- Extracted official runtime SHA256: `cb40d5867033badfa1a38072fab83f1c60ec1520c303a4810f49979f0ba5df04`
- Retained release directory:
  `/tmp/opencode/ci-43726942646-debian-artifact/deb-release`

Package/source hashes were verified before use. The runtime hash was measured
from the actual Debian payload and checked again against the guest's verified
payload manifest. No custom export, engine patch, AOT swap, SDK invocation,
renderer flag, or alternate launcher was used. Existing app retention was intact.

## Cached official guest image

The existing `/tmp/lllf-debian-12.qcow2` was reused, with no new image download.
It matched both its retained SHA256 sidecar and the official SHA512SUMS entry
for `debian-12-genericcloud-amd64.qcow2`.

- SHA256: `24036a8b79cbb11d809752c60f2f885b1a3b02b1d663faa0b648eb87bd7a256e`
- SHA512: `0464b5d4ae3aa4f658468d88da83af7857b71548b30d46dcb6282770955a747fb95a983476db90d25afd0653af607224c7ebd05122ab71faa106fd712aaad652`

Guest: Debian 12/bookworm, kernel `6.1.0-54-cloud-amd64`, AMD Ryzen 7 7840HS.
Runtime libraries: libc `2.36-9+deb12u14`, GTK `3.24.38-2~deb12u3`, Mesa
`22.3.6-1+deb12u2`, LLVM `15.0.6-4+b1`. Host CPU/kernel/QEMU are retained in
`host-and-inputs.txt`; QEMU is `11.1.2` on the local Linux host.

The standard guest package provisioning was preserved. The approved capture
overlay adds GDB/binutils/systemd-coredump and the previously documented AT-SPI
service. No extra graphics-library upgrade or retry was introduced for a pass.
The existing inherited root XDG_RUNTIME_DIR still caused dconf warnings in the
accessibility subprocess; they remain in the logs. The app's unchanged close
and critical-error gates passed. No warning was filtered or silently fixed by
rerunning the app.

## Executed command

Harness branch `diagnostic/official-debian12`, commit
`840fc36` (based on `77a189e`), uses only the four previously approved test
files and independent-error collector. The package/source bytes are separate
and unchanged. The opt-in core flag is set to **1**, not 20:

```bash
timeout -k 30s 2100s nix shell nixpkgs#cloud-utils -c env \
  LLLF_VM_ACCELERATOR=kvm LLLF_DEB_CORE_DIAGNOSTIC_ATTEMPTS=1 \
  bash tool/test_portable_distro.sh /tmp/lllf-debian-12.qcow2 \
  24036a8b79cbb11d809752c60f2f885b1a3b02b1d663faa0b648eb87bd7a256e \
  /tmp/opencode/official-debian12-43726942646/vm --deb \
  /tmp/opencode/ci-43726942646-debian-artifact/deb-release
```

The standard user command, window assertion, normal-close behavior and full
package/helper contract ran inside the VM. The diagnostic manifest explicitly
identifies instrumentation rather than claiming an untouched release harness.
Bash/Python syntax and diff checks passed before execution.

## Retained evidence

Root: `/tmp/opencode/official-debian12-43726942646/`

- `host-and-inputs.txt`: host, image, input hashes and harness commit
- `qualification-command.log` and `.exit`: bounded command output/status
- `vm/`: qualification log, journal, serial output, manifests and archives
- `extracted/`: package check results, runtime manifest, fixture core, GDB
  backtrace/mappings/statuses and guest environment

SHA256:

- Qualification log: `9c973be905fe7f708bf96cca0b7c89e587c84ce171c2ecffddec67fcd5e8dbb1`
- Core diagnostic archive: `88d419de9ab24b2d48470d68c040c6f629c42a5f55775f4853741a488cb37042`
- Package qualification archive: `17ebaee6ca11e4976b9cde50f7a4ba55801d39d4c0057dc8be28033406040b9f`

No Ubuntu rerun, build, full CI run, icon change, convenience-link update,
tag, release, or merge occurred. PR 9 and main remain under the parent's control.
