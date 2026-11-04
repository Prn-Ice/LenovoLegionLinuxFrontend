# Model support and testing

Some features may not work on every model. Run diagnostics to find out why.

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
