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

An empty table is more accurate than fabricated support. Add entries only when
there is an issue/PR or other reviewable evidence. This guide intentionally does
not assert a tested-model list until contributors provide those reports.
