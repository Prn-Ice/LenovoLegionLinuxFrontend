# App helper on Ubuntu

Build and test the production helper in a disposable Ubuntu 22.04 VM before
packaging it for Debian-family desktops and AppImage. This checks the helper
against Ubuntu's libraries. AppImage recommends building on the oldest
intended base system because newer glibc dependencies prevent older systems
from loading a binary. See the [AppImage build guidance](https://docs.appimage.org/reference/best-practices.html).

The check builds C++ sources inside the guest, runs the nine native test targets,
and exercises the production helper from a user-owned path containing spaces.
The CLI is the existing VM-only synthetic executable. The tests check typed
write/readback/restore, request validation, denial, a missing authentication
agent, incompatible CLI help, startup deadlines, crash containment, and the
shared hardware write lock. They compare persistent integration files before
and after portable use.

Ubuntu's local-authority Polkit fixture grants the approved test user access and
rejects the denied user. A third user requires authentication with no agent
available. These policies exist only in the guest. See Ubuntu's
[local-authority format](https://manpages.ubuntu.com/manpages/jammy/man8/pklocalauthority.8.html).
Desktop password dialogs and cancellation need separate qualification.

## Verified environment

Passed on 2026-11-11 in an x86-64 Ubuntu 22.04.5 LTS VM:

| Component | Ubuntu package version |
| --- | --- |
| systemd | 249.11-0ubuntu3.23 |
| glibc | 2.35-0ubuntu3.15 |
| GLib/GIO | 2.72.4-0ubuntu2.11 |
| Polkit | 0.105-33ubuntu0.2 |

All nine native test targets passed as an ordinary user. The executable ownership
and snapshot checks also passed as root with every case enabled. The production
helper session checks passed, and portable use preserved the persistent service,
Polkit, D-Bus, and udev files inspected by the test. ShellCheck, actionlint, and
the former Python lint check passed for the scripts and workflow at that commit.
Those results predate the Bash test port; rerun qualification for current evidence.

## Run locally

Install Dart 3.14 or newer, QEMU, `cloud-localds`, OpenSSH clients, `jq`, and `ss`.
The project's Flutter SDK includes Dart. On Debian/Ubuntu,
their packages are `qemu-system-x86`, `qemu-utils`, `cloud-image-utils`,
`openssh-client`, `jq`, and `iproute2`. On Nix, use the pinned Nixpkgs versions of
`qemu`, `cloud-utils`, `openssh`, `jq`, and `iproute2`.

The shared session, desktop, and distro tests run in Bash inside the guest. NixOS
tests retain only the upstream Python driver's VM-start, command, and evidence-copy
calls; their assertions and scenarios also run in guest-side Bash. The VMs need
neither Python for project tests nor a Dart or Flutter SDK.

Run the hardware-free runner regressions before building a VM:

```bash
bash test/tool/distro_evidence_test.sh
bash test/tool/distro_readiness_test.sh
```

The first command checks failure-status preservation and partial evidence archives.
The second checks cloud-init deadlines, SSH retries, and remote failure statuses.

Download the official image and its checksums, then run from the repository:

```bash
curl -fL https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -o /tmp/jammy.img
curl -fL https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS -o /tmp/jammy.SHA256SUMS
checksum="$(awk '$2 == "*jammy-server-cloudimg-amd64.img" {print $1}' /tmp/jammy.SHA256SUMS)"
bash tool/test_distro.sh /tmp/jammy.img "$checksum" build/ubuntu-qualification
```

The runner verifies the supplied image checksum and creates a temporary overlay.
It starts QEMU as the current user with SSH bound to loopback. QEMU uses KVM when
accessible and software emulation otherwise. CI grants the runner access to
`/dev/kvm` when that device exists. Set `LLLF_VM_ACCELERATOR=tcg` to reproduce
software emulation on a KVM host. The guest downloads its build dependencies
over the network. The runner copies native source directories into the VM and runs the
setup script there. It terminates the VM and deletes the disk overlay and
temporary SSH key on exit. It requires an unused output directory.

## Saved test results

The output retains boot, build, test, and system logs. The JSON file
`manifest.json`, called a qualification manifest in the tools, records which
source commit and test-system image were used, whether the source had local
edits, which checks passed, and what remains unverified.

It also records checksums of the source and test-result archives. A checksum
identifies a file's contents. The release tools compare these values to confirm
that the saved results belong to the package being released.

The test-result archive contains the helper,
ELF headers, and exact distro package versions. CI runs this check inside AppImage
acceptance and includes `appimage-native-qualification.tar.gz` in that job's
AppImage evidence archive, rather than repeating it in another VM.

The host writes this JSON file through `tool/record_package_test_results.dart` after
the guest succeeds and its evidence archive is retrieved. CI uses the same tool
to add the NixOS evidence archive hash after NixOS acceptance succeeds. Both
operations use the existing JSON format; the NixOS update preserves its
other fields. Failed qualification or evidence retrieval stops the shell runner
before it records a successful test run.

This native helper check uses the host loader cache and host libraries and
rejects an RPATH or RUNPATH in that binary. The [AppImage check](../appimage.md)
separately builds a static helper, bundles the desktop runtime, and exercises
FUSE and extracted launch without host GTK. Its NixOS VM launches the same
AppImage through official `appimage-run` and exercises a GUI hardware change
and restoration against synthetic kernel files and a synthetic CLI. Actual CLI
imports/configuration, desktop approval, and hardware writes need separate
evidence.
