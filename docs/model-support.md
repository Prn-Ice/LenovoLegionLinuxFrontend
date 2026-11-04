# Model support and testing

Model support is a collection of feature-specific observations, not a promise
that every control works. Use diagnostics to identify whether a gap belongs to
the kernel module/backend, frontend discovery, or keyboard HID support. A
frontend profile cannot add missing driver support.

## Add or correct support

1. Open a GitHub issue with the laptop model identifier and the feature or
   mismatch. Attach sanitized diagnostics when available; remove serial numbers,
   usernames, and other identifying data.
2. Record BIOS, kernel, module, backend, and relevant device/protocol details.
   Say explicitly which features you tested and which remain unknown.
3. Reproduce discovery or parsing behavior with a small sanitized fixture. Add
   or update the relevant test so contributors without the laptop can verify it.
4. Change the narrow boundary that owns the behavior: driver/backend issue,
   frontend discovery, or tested keyboard mapping. Do not guess a fallback for
   unknown hardware.
5. Test on the affected machine when possible, then submit a pull request linking
   the issue, fixture, fix, and completed entry below. Clearly mark any checks
   not performed.

For keyboard lighting, include the USB vendor/product ID and evidence for the
protocol, physical layout, and brightness calibration. For sysfs-backed
features, distinguish a readable value from a verified writable capability.

## Worked example: missing fan reading

Suppose an owner's diagnostics show a Legion fan provider that the frontend
does not select. This is a hypothetical discovery fix, not a support claim.

1. Inspect `lib/core/services/legion_sysfs_service.dart`, starting with
   `readFan1Rpm` and its discovery helpers. Compare the reported provider name,
   paths, and readable inputs with the selection rule.
2. Add a regression case to
   `test/core/services/legion_sysfs_service_fan_discovery_test.dart`. Follow its
   temporary-directory setup and teardown: copy only the relevant sanitized
   provider name and `fan1_input` value, recreate required links inside the
   temporary tree, and inject the fixture paths into `LegionSysfsService`.
   Assert the expected RPM and that an unrelated provider is not selected.
3. Change the selection rule in the service only if the evidence identifies the
   correct source. Preserve unknown results for unrecognized providers.
4. Run the focused test from the repository root:

   ```bash
   flutter test test/core/services/legion_sysfs_service_fan_discovery_test.dart
   ```

5. Ask the owner to verify the readout and attach that result to the issue.
   Record fan readings as tested; fan writes and other features remain untested
   unless separately checked.

The broader discovery work adds `sysfsRoot` and `procRoot` constructor inputs.
After that change is integrated, the same fixture pattern can use
`LegionSysfsService(sysfsRoot: '${root.path}/sys', procRoot: '${root.path}/proc')`.
For example, hypothetical fixture files under `sys/class/hwmon/` belong inside
that temporary `sys` directory, not the host `/sys`. Use the constructor inputs
available in your checkout; the existing fan tests use `hwmonRoot` and
`fanHwmonRoot`. Keep all fixture writes and symlink targets inside the test tree.

## Tested-model entry template

Copy this template for an actual test report. Do not fill unknown fields by
inference, and do not claim untested features work.

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
