# Linux shutdown qualification

The deployment target remains official Flutter 3.50.0 with the small engine
retention fix from `a3c9262`. On 16 November 2026, the user rejected custom-engine
adoption and chose to continue with the official SDK. The isolated patches and
packages described below are not deployment inputs.

## Current decision: investigation deferred

On 17 November 2026, the user chose to proceed with deployment and document
this issue for later unless a concrete cause and simple supported fix are
available. The retained traces identify a lifecycle failure class, but the
investigation found no supported minimal app fix. Track it as deferred in
`lllf-dt0.5.16`; do not repeat the rejected experiments or rebuild unchanged
artifacts to search for a green run.

Newer official-SDK packages passed all ten jobs in merged-main
[CI run 44094959984](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/actions/runs/44094959984)
at `404980d`. This is successful acceptance of that candidate, not proof that
the historical crash is fixed. The issue no longer blocks deployment work by
itself. Existing launch, close, authorization, and cleanup checks still apply
to every release candidate; a failed check still stops release preparation.

## What fails

Closing the app can crash the process. In the NixOS AppImage VM, the main thread
reaches process exit while Flutter's raster thread still calls Mesa's
`glReadPixels`. Mesa can then free resources that the raster thread still uses.
This is separate from cancelling authentication for the privileged control helper.

Explicitly destroying the retained window after the application loop stops also
failed. GTK destroys Flutter's renderer while its frame mutex can still be in
use, producing `g_mutex_clear() called on uninitialised or locked mutex`. Completing
queued main-context work did not prevent that failure. These experiments were
removed; they are not release fixes.

## Official-SDK evidence

| Candidate | Result |
| --- | --- |
| Flutter 3.47.9, commit `3cf5fdc` | NixOS AppImage crashed on its first Settings close in Mesa readback. |
| Flutter 3.50.0 / Yaru 12, commit `adab917` | The same NixOS close failure; Ubuntu AppImage launch/close and Debian installation checks passed. |
| Experimental native cleanup, commit `966154c` | NixOS AppImage and Debian 12 aborted during normal window close. The experiment was reverted in `1db619b`. |
| Flutter 3.50.0 / Yaru 12, PR #9 head `77a189e`, CI merge `e1c1d53` | [Final combined CI](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/actions/runs/43726942646) passed every job except Debian package acceptance. Ubuntu 22.04 rendered Dashboard, then normal close exited `-11` with a raster-thread fault in `libLLVM-15.so.1`. Debian 12 did not run. The AppImage matrix passed, including ten X11 and ten Wayland closes. |
| Same exact Debian package, hosted diagnostic | [Run 43735297027](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/actions/runs/43735297027) reproduced the first-close `-11` on AMD EPYC 9V45 after proving core capture. The core shows main-thread libc `exit` overlapping Flutter raster work in LLVM JIT/Mesa. This is the same lifecycle class as the NixOS evidence, not the identical Mesa readback stack. |

The historical failed CI package SHA256 is
`3b169c4d1fe8cb684c958363ded0a43b399b1dfed226e390ef023af06a85bae2`;
its source companion SHA256 is
`321ec05b544d4977d0634fbcd088873d7a5669f07d5561fe6c3ed60686145162`.
Both identify CI merge `e1c1d5392db90a78a46da43b9c45d9caf2672311`, whose
second parent is PR #9 head `77a189e`. Diagnostic artifact `14170452029` retains
the app core and all-thread stack; its SHA256 is
`ddceabf0175a990b26b42f34a2d6b88c5a4d78f7c906d60fa051fb4cc7f643d9`.
The local evidence summary is
`/tmp/opencode/pr10-hosted-core-diagnostic-summary.md`.

Local packages, source manifests, and logs are retained under
`build/qualification/adab917/rejected-shutdown/` and
`build/qualification/966154c/rejected-shutdown/`. Each directory records its
rejected status. Neither candidate replaced `build/legion-frontend.AppImage`.

The SDK upgrade passed generation, analysis, 777 Flutter tests, 24 visual
renders, 14 native app journeys and both restart phases, four native codec tests,
and the Nix package/source check. Those results do not establish clean shutdown
for every package and graphics environment. The earlier user-tested build
`46b827e` used Flutter 3.47.9. On 16 November, after receiving the retained
official 3.50.0 AppImage command (SHA256 `ae10838f…d5afbe`), the user reported
that it works and confirmed that retry works too. This records a successful
hardware trial; hardware readback, restoration, helper cleanup, and numeric
process exit status were not explicitly reported. The separate Debian failure
remains unresolved.

## Upstream work

Flutter's open, Linux-triaged
[engine shutdown issue](https://github.com/flutter/flutter/issues/132404)
records the same lifecycle gap: the GTK application loop returns before the
Linux embedder shuts down the Flutter engine and Dart root isolate. In the exact
Flutter 3.50.0 source, the normal exit path detaches the GTK windows and quits
`GApplication`; it does not stop the engine.

Flutter 3.50.0's public `FlEngine` API has no stop, shutdown, renderer-fence, or
idle-wait operation. Engine shutdown occurs only during internal GObject
disposal. The runner cannot request that sequence through a supported API, and
forcing disposal reaches the renderer race described above. Framework exit APIs
use the same native exit path, so they do not provide an app-level mitigation.

Flutter's [renderer lifetime work](https://github.com/flutter/flutter/pull/193533)
proposes moving mutex and task-runner cleanup until raster references are gone
and synchronizing graphics-resource teardown. It remains open and is not in
Flutter 3.50.0. Related
[deferred window destruction work](https://github.com/flutter/flutter/pull/193126)
addresses teardown during nested GTK drawing. Both proposals remain open as
checked on 16 November 2026. The isolated experiment below tested these patches;
they are not fixes available in the official 3.50.0 SDK.

The separate [task-runner fix](https://github.com/flutter/flutter/pull/194525)
was merged upstream but is absent from the exact 3.50.0 engine revision
`371f77202a73e8dff57a8b3bff75bca55c090aee`. Keep the existing approved engine
retention until a compatible fix passes repeated-close checks
(`lllf-dt0.5.13`).

## Isolated experiment: rejected for deployment

`lllf-dt0.5.16.1` tested patches from upstream PRs 194525, 193533, and 193126
against the pinned 3.50.0 source in a separate engine. Variant A kept the app's
engine retention; variant B removed it.

- A passed 20 Ubuntu closes and 22 NixOS functional/X11/Wayland closes locally.
  [One hosted comparison](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/actions/runs/43888451162)
  also passed 20 Ubuntu closes and the existing helper/package checks.
- B aborted on its first Ubuntu close (`-6`), with LLVM/Mesa raster work
  overlapping process exit. Its separate NixOS flow passed 22 closes.

A's passes are bounded non-reproduction, not proof of shutdown synchronization.
B does not justify removing retention. The original official-SDK failures remain
unresolved. Diagnostic PRs #10 and #11 closed unmerged; neither changed PR #9,
main, the shared SDK, or the user's convenience artifact.

The local reports are `/tmp/opencode/lllf-shutdown-results/RESULTS.md` and
`/tmp/opencode/patched-a-hosted-43888451162/RESULT.md`; hosted artifact
`14235153844` retains the A comparison. Optional collector follow-up
`lllf-dt0.5.16.1.2` does not block assessment of the official candidate.

## When to reopen the investigation

Resume only when new evidence identifies a concrete cause and a small supported
fix, or an official stable SDK includes a relevant upstream fix. Record that
evidence and the proposed change before testing it. If a bounded check does not
establish the fix, retain its result and defer again; do not expand into another
custom-engine or speculative cleanup experiment.

Keep official Flutter 3.50.0 and the approved engine retention for current
deployment. The isolated engine remains rejected. Test a future supported fix
with the standard launch commands and existing X11/Wayland close matrix,
requiring exit status zero and no GLib/GObject critical errors. Authorization,
readback, restoration, and helper cleanup must still pass.

See [deployment status](releases.md#deployment-status-17-november-2026) for the
current candidate and remaining release work. No release tag or GitHub release
was created during this investigation.
