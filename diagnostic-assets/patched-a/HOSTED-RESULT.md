# Hosted patched A result

Run [43888451162](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/actions/runs/43888451162),
job `133372847769`, completed successfully in 2m52s at diagnostic commit
`49b84e0a2e78416746c6c182ad8a6db810cd9e44`.

## Actual checks

- Approved-user core fixture: passed before app launch. Soft and hard core
  limits were unlimited; Python aborted with SIGABRT; its raw core, GDB
  `pthread_kill -> raise -> abort` stack, and mappings were retained. Both GDB
  status fields were zero.
- Dashboard and ordinary normal close: **20/20 required attempts passed**.
  Each app exited zero. No attempt was a retry after an app failure.
- Installation/payload verification, helper approval, denial, missing agent,
  readback/restore, upgrade, purge, and persistent-file preservation: passed.
- Qualification, collection, and archive statuses: all zero.
- No app failure/core occurred. The only coredump was the controlled fixture.

This is bounded hosted non-reproduction, not proof of shutdown synchronization,
a confirmed fix, release qualification, or approval to adopt a custom engine.
The earlier stock raster/exit overlap and B's first-close abort remain evidence.
No engine rebuild, B test, NixOS rerun, or full CI matrix ran in this task.

## Exact existing inputs

- A app package source: `61367a98775765d1144f2d9bd50a1a124a1ce7df`
- Package SHA256: `58cdf3943cc5b5650186cd484f7a918918f78af7781a5e2e4ba575422f5d4f43`
- Source SHA256: `eac236abd2fa6eaae4780a8963768218438fce6e57aed780569bbdb6fcc19c64`
- Runtime SHA256: `226a06ff64e17e4cc2468af63be9f2b737fddd680a8ae34e7e5c7c026bb506ad`
- Runtime build ID: `50fc1e9aa3a2f684cc9837bdfad045a735589fbe`

The workflow restored the existing staged files and verified their original
hashes, the experimental A manifest, and the runtime payload inventory before
launch. The normal installed launcher, Dashboard assertion, close assertion,
and helper/package checks were unchanged. No old manifest or AOT was reused.

## Actual environment

- Standard `ubuntu-latest` host: Ubuntu 26.04, kernel `7.0.0-1019-azure`
- Host/guest CPU: AMD EPYC 7763 64-Core Processor; no CPU-vendor gate
- Host QEMU: `10.2.1`, package `1:10.2.1+ds-1ubuntu3.3`
- KVM guest: Ubuntu 22.04.5, kernel `5.15.0-203-generic`
- Guest image SHA256: `77d19e53656f87c95f1f6c6be59c789083b3f77fa08f9d88011ee04085c61f87`
- Mesa: `23.2.1-1ubuntu3.1~22.04.4`; LLVM: `15.0.7-0ubuntu0.22.04.3`

The host label, QEMU package, guest image family, and rendering packages match
the intended reproduction flow. CPU allocation differs from the prior Xeon
8573C and EPYC 9V45 failures; no claim of identical host hardware is made.
The experiment harness includes its recorded AT-SPI service provisioning.

## Retained evidence

- Hosted artifact: `14235153844` (`patched-a-core-43888451162`), seven-day retention
- Artifact SHA256: `7943e012ed0af86b4a9a4d63494337e8922029a015c3503b64fa0aedd79a79ec`
- Job-log SHA256: `e98237b945d12e83e428b4d8113817f9ed98f60211d227ee498e10b9101e86e5`
- Qualification-log SHA256: `2746261110f416498bd389bf59efd89b0eba336683bbd4dd80725ce385c31f0c`
- Fixture-core SHA256: `2fa168e558f51d5d0577fb711b4a7e14168020ef0e00f9516667782ab0329d2e`
- Downloaded/extracted evidence: `/tmp/opencode/patched-a-hosted-43888451162/`
- Full job log: `/tmp/opencode/patched-a-hosted-43888451162-job.log`

## Scope and collector check

Temporary draft PR 11 is diagnostic-only and must be closed unmerged after
evidence collection. Staged assets stay off normal branches and are not a
release. PR 9, main, the shared SDK, export, and convenience artifacts remain
unchanged.

The collector now runs backtrace and mapping commands independently, records
their separate statuses, continues to build-ID/library archiving after a GDB
error, and returns that collection error without replacing an app failure.
A focused fake-GDB fixture verified that a forced backtrace exit 7 still runs
the mapping command and retains both statuses. This successful app run did not
exercise collection of a real failed app; that limitation remains explicit.
Actionlint, ShellCheck, Bash/Python syntax, and diff checks passed.
