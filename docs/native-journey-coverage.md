# Native Linux journey coverage

These tests launch the Linux app and operate its controls. They are not widget
tests rendered in place of an app window. Feature state and navigation remain
real; fixtures replace external hardware, processes, and selected Settings
status repositories. No journey starts a privileged helper or changes hardware.

## Run

From the development shell and a Linux desktop session:

```bash
flutter pub get --enforce-lockfile
bash tool/test_linux_journeys.sh
```

For a short navigation check:

```bash
flutter test integration_test/smoke_test.dart -d linux --no-pub
```

For a headless X11 run, invoke the same commands under `xvfb-run -a`, with
`GDK_BACKEND=x11` and `GSETTINGS_BACKEND=memory`. Keep Flutter commands serial
within a checkout.

The full runner starts the regular scenarios, two keyboard restart processes,
and two appearance restart processes. Each restart pair shares its own temporary
storage and verifies distinct process IDs. The runner removes only its fixture
directories, including on failure.

The regular suite has a ten-minute process limit to include all sections and a
cold native build. Individual state waits still fail after fifteen seconds;
each restart process retains its three-minute limit. The runner stops at the
first failed process and does not retry failures.

## What is covered

| Section or contract | Native checks |
| --- | --- |
| Dashboard | Battery confirmation cancellation/apply, typed failure recovery, pending-write controls, explicit power-mode refresh |
| Power | Profile readback and AC constraints; staged limits, Revert, grouped apply, rollback/retry; rapid-charging confirmation and readback |
| Fans | Preset cancellation/apply; bounded CPU/GPU point edits; full-table save/readback; rejected or unchanged saves preserve drafts; Refresh reloads readings without discarding drafts |
| Battery | Conservation cross-page readback, unavailable hardware, charging readback mismatch/unavailability, completion after navigation away from Power |
| Lighting | Real OpenRGB service failure/retry using synthetic process results; native Spectrum discovery, calibrated HID reports, software-animation frames and disposal |
| Automation | Named profiles, current/observed-mode assignments, manual edits, missing-profile recovery, failed apply/retry, app-lifetime switching |
| Settings and diagnostics | Unsupported status snapshots, diagnostics opening/copy/redaction, native compact-window navigation and selection, appearance persistence |
| Whole app | All eight main sections render actionable content without uncaught errors or privileged requests |
| Process restart | Named lighting profile/configuration and appearance preferences survive separate real app processes |
| Shared safety | Denied authorization, unavailable service, command rejection, accepted-but-unchanged or missing readback, pending writes, truthful failure and retry |

The navigation smoke entrypoint is also registered in the full suite. Its
success is a navigation/read-only check, not a replacement for write journeys.

## Fixture boundaries

- Hardware readings use temporary sysfs files. The typed control client and
  repositories run normally; the transport accepts only listed operations.
- Graphics retains the real repository and Bloc. Optional callbacks replace PCI
  and process reads, while a synthetic CLI response supplies authoritative
  graphics status. Selected mode and observed topology are independent.
- Native Spectrum retains discovery, LED mapping, calibration, report
  construction, repository, effect engine, and Bloc. A typed HID I/O fixture
  replaces libc calls; the actual `/dev/hidraw` interface is never opened.
  OpenRGB discovery is deliberately unavailable in this case.
- OpenRGB journeys retain the real CLI service but replace its process runner.
- Settings hardware-status repositories supply synthetic snapshots. The
  diagnostics route, report builder, clipboard operation, Settings Bloc, and
  appearance store remain real. This does not qualify host report collection.
- Appearance and lighting stores use isolated Hive files. Caller-owned restart
  roots survive app disposal until the runner removes them.

Fixture values are synthetic inputs chosen to expose transitions, not laptop
measurements or recommended hardware defaults.

## Deliberate limits

These journeys do not qualify real hardware, Polkit dialogs, privileged helper
deployment, renderer/window-close compatibility, or package installation.
Package acceptance and hardware read/write/readback/restore remain separate
lanes. Provider disposal verifies the software-animation lifetime; it is not
evidence that every desktop package closes normally.

OS-owned file pickers, boot-logo upload, and diagnostic file export are not
automated here. Clipboard export is covered without pretending to exercise an
OS file dialog. Boot-logo status in Settings is synthetic and read-only.

Native Spectrum service failures have unit coverage. The broader manual-lighting
false-result handling and remaining requested-versus-observed checks are still
tracked in `lllf-6p0`; success-path coverage does not resolve those product bugs.

Current GitHub PR workflows run commit-convention and security checks.
Native/app/package validation is invoked by tagged releases, not PRs. Local
native results and release CI results must be reported separately.
