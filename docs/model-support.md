# Model support and testing

Development and hardware testing currently use one physical laptop: the project
owner's **Legion Slim 7 16APH8 (82Y4, BIOS M1CN48WW)**. Not every feature has
been verified on it. Other models and BIOS versions are unverified, even when
the upstream driver supports them. See [feature readiness](../README.md#features-and-readiness)
and the [community backlog](../BACKLOG.md) for current limits and work.

Diagnostics help identify available readings and missing support; they do not
certify a model or verify hardware writes.

## Collect a discovery report

Open **Diagnostics**, refresh, then choose **Copy report JSON** in Environment.
The existing report includes the model family, model identifier, BIOS, kernel,
module and CLI versions, plus the results of reading hardware files. Each check
exports
`read.outcome`, `read.selected_path`, and ordered `read.attempts` with paths and
outcomes. Invalid file contents are omitted. Fan checks name the driver used for
the reading when its name is available. The first 32 hwmon driver names, sorted
by path, help identify layouts the app does not yet recognize. Reading a driver
name does not tell us whether its sensors work.

- `readable`: the selected file returned a value in the expected format.
- `missing`: the checked path does not exist.
- `unreadable`: access was denied or the path could not be read as a file.
- `malformed`: the content was empty, invalid UTF-8, too long, or not in the
  expected value format.
- `unknown`: no matching hardware provider was found, or an unexpected file error
  prevented a result. The directory checks show whether the search location was
  missing or could not be read. Unknown does not mean unsupported.

`frontend_write_available` means the app has code to change that setting. The
driver may still reject it, and the control may be disabled. The report separately
records whether the control service is running (`control_service_active`). Writes
are marked `unverified`: diagnostics do not change settings or test whether a
previous command changed the hardware.

The report includes only the named model and BIOS fields. Serial numbers, UUIDs,
host/user names, the local CLI path, and raw CLI errors are excluded. Paths in
command arguments are replaced with `<path>`. Review the report before posting
it, and describe any settings you tested manually alongside it.

`test/fixtures/sysfs/alternate-layout.json` contains **synthetic test data** chosen
to exercise alternate Ideapad, LED, mains and `yogafan` paths. It was not recorded
from a laptop. Tests create files under `Directory.systemTemp` and point the
service's sys/proc roots there. To test an unreadable file even when running as
root, they put a directory where a file should be.

```bash
flutter test test/core/services/legion_sysfs_diagnostics_test.dart test/features/about/about_repository_test.dart
```

## Report or fix a problem

1. Open a GitHub issue with your laptop model and the problem. Attach diagnostics
   if available. Remove serial numbers, usernames, and other personal information.
2. Include your BIOS, kernel, driver, and CLI versions. List what you tested and
   the results.
3. Add a test using a small sample of the diagnostic data, with personal
   information removed. The test should run without the laptop.
4. Fix the problem in the driver, app, or keyboard mapping, as needed. Do not
   guess settings for unknown hardware.
5. If possible, test the fix on the affected laptop. Link the issue and test
   results in your pull request, and fill in the template below. Note anything
   you could not test.

For keyboard lighting, include the USB vendor and product IDs, protocol, key
layout, and brightness test results. For sysfs features, report reading and
writing separately.

## Example: missing fan reading

Suppose diagnostics show a fan sensor that the app does not detect.

1. Inspect `lib/core/services/legion_sysfs_service.dart`, starting with
   `readFan1Rpm` and its discovery helpers. Compare the reported provider name,
   paths, and readable inputs with the selection rule.
2. Add a regression case to
   `test/core/services/legion_sysfs_service_fan_discovery_test.dart`. Follow its
   temporary-directory setup and teardown: copy only the relevant sanitized
   provider name and `fan1_input` value, recreate required links inside the
   temporary tree, and inject the fixture paths into `LegionSysfsService`.
   Assert the expected RPM and that an unrelated provider is not selected.
3. Update detection only when the diagnostics identify the correct sensor.
   Keep unknown results for unidentified sensors.
4. Run the focused test from the repository root:

   ```bash
   flutter test test/core/services/legion_sysfs_service_fan_discovery_test.dart
   ```

5. Ask the owner to check the fan reading and post the result in the issue.
   Record only the features they tested.

Use the `sysRoot` and `procRoot` constructor inputs for broader discovery fixtures:
`LegionSysfsService(sysRoot: '${root.path}/sys', procRoot: '${root.path}/proc')`.
Fixture files under `sys/class/hwmon/` belong inside
that temporary `sys` directory, not the host `/sys`. The narrower fan tests can
also use `hwmonRoot` and `fanHwmonRoot`. Keep all fixture writes and symlink
targets inside the test tree.

## Add model-specific data

Power and temperature settings recorded from an `82Y4` laptop with `M1CN48WW`
BIOS were chosen as the app's defaults for that model and BIOS. They live in
`lib/features/power/models/power_model_defaults.dart`. The Power page shows them
beside current settings. See [the capture notes](power-defaults-evidence.md) for
where the numbers came from. Add another entry only with its model, BIOS, recorded
values, and an explanation of why those values should be used. Extend
`test/features/power/power_model_defaults_test.dart` so nearby BIOS versions and
unknown models do not inherit them.

Native keyboard data lives in `lib/features/lighting/models/`:

- `spectrum_keyboard_profile.dart`: USB IDs, packet format, and measured color
  adjustments for each supported keyboard.
- `spectrum_led_map.dart`: the LED address controlled by each key name.
- `keyboard_layout.dart`: key positions and sizes used in the preview.

Diagnostics also read Linux HID `uevent` files under `/sys/class/hidraw` to
record the vendor/product IDs, selected hidraw node, known profile, protocol,
and a clear missing/unsupported/unreadable/malformed result. This discovery is
read-only and does not open the device or send keyboard packets. Copied report
JSON includes normal `/dev/hidrawN` paths, hides custom directory names, and
omits serial and `HID_UNIQ` data.

For a new keyboard, record its exact USB IDs and verify its LED addresses,
layout, and brightness behavior. Add a profile and a small `uevent` sample under
`test/fixtures/lighting/spectrum/`, explaining whether the sample was recorded or
invented for the test. Test unknown IDs as well as the new keyboard. The native
service currently targets `048d:c987`; selecting another profile also requires
passing its IDs to `SpectrumHidService`. Only the Gen 7/8 packet format is
implemented.

Run the data and keyboard tests without connecting hardware:

```bash
flutter test test/features/power/power_model_defaults_test.dart test/features/lighting
```

## Recorded read-only check: 82Y4 / M1CN48WW

On 2026-11-04, the app's readers were checked on the project owner's Legion Slim
7 16APH8 with kernel `7.3.1`, running on battery in `low-power` mode. They found
both fan readings through `legion_hwmon`, the selected CPU/GPU power files, and
the adapter and battery-conservation state. Native keyboard discovery found
`048d:c987` at `/dev/hidraw0` using the Gen 7/8 profile without opening the device.

The control and telemetry services were active. The module version file was
absent, and the installed CLI rejected `--version`, so their versions remain
unknown. `minifancurve` was unreadable; camera and white-backlight files were
absent.

A separately approved battery-conservation test used `LegionControlClient` over
system D-Bus to change the setting from off to on, read back on, then restore
off and read back off. Authorization and both writes succeeded. Other hardware
write operations remain untested.

The [recorded sample](../test/fixtures/sysfs/82y4-m1cn48ww-readonly.json) and
[capture notes](../test/fixtures/sysfs/README.md) preserve the paths and readings
used by the hardware-free replay test.

## Tested-model entry template

Use `unknown` or `not tested` where needed.

```markdown
### <manufacturer and model identifier>

- BIOS/firmware: <version or unknown>
- Kernel: <version and distribution>
- Module: <name and version/commit, or not installed>
- Backend/CLI: <name and version/commit, or not installed>
- Frontend: <release or commit>
- Test date: <YYYY-MM-DD>
- Features tested: <feature — observed result; include read/write distinction>
- Known gaps: <unsupported, failed, or not tested>
- Evidence: <linked issue/PR and sanitized diagnostics or fixture>
```
