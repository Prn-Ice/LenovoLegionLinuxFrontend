# Portable helper on Ubuntu

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
Pyflakes passed for the new scripts and workflow.

## Run locally

Install QEMU, `cloud-localds`, OpenSSH clients, and Python 3. On Debian/Ubuntu,
their packages are `qemu-system-x86`, `qemu-utils`, `cloud-image-utils`,
`openssh-client`, and `python3`. On Nix, use the pinned Nixpkgs versions of
`qemu`, `cloud-utils`, `openssh`, and `python3`.

Download the official image and its checksums, then run from the repository:

```bash
curl -fL https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -o /tmp/jammy.img
curl -fL https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS -o /tmp/jammy.SHA256SUMS
checksum="$(awk '$2 == "*jammy-server-cloudimg-amd64.img" {print $1}' /tmp/jammy.SHA256SUMS)"
bash tool/test_portable_distro.sh /tmp/jammy.img "$checksum" build/ubuntu-qualification
```

The runner verifies the supplied image checksum and creates a temporary overlay.
It starts QEMU as the current user with SSH bound to loopback. KVM is used when
accessible; otherwise QEMU uses software emulation. The guest downloads its build
dependencies over the network. The runner copies native source directories into
the VM and runs the setup script there. It terminates the VM and deletes the disk
overlay and temporary SSH key on exit. It requires an unused output directory.

The output retains boot, build, test, and system logs. `manifest.json` records the
source commit, modified source status, cloud-image checksum, source archive hash,
and qualification archive hash. The qualification archive contains the helper,
ELF headers, and exact distro package versions. CI retains these files in the
`portable-ubuntu-22.04-qualification` artifact.

This native helper check uses the host loader cache and host libraries and
rejects an RPATH or RUNPATH in that binary. The [AppImage check](../appimage.md)
separately builds a static helper, bundles the desktop runtime, and exercises
FUSE and extracted launch without host GTK. Its NixOS VM launches the same
AppImage directly with standard `nix-ld` and FUSE support. Actual CLI
imports/configuration, desktop approval, and hardware writes need separate
evidence.
