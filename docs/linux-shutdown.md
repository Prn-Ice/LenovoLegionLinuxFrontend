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

## Isolated stable/beta comparison: 18 November 2026

The user approved this bounded comparison in `lllf-b68.4`, not a production
upgrade or removal of engine retention. **Beta did not demonstrate an improvement
in the reported shutdown failure.** Both SDKs completed the comparable Ubuntu
checks without reproducing it. The host comparison stopped at a beta build
blocker; stable also exposed a different, Yaru window-state crash.

The app source was main `34539dd24463189d90c7dc6f3e7fdfa0342f155c`, with its
unchanged native runner and retention. Separate checkouts, SDK directories, and
fresh HOME/XDG storage kept the experiment away from user data. No hardware
settings, installed services, shared SDKs, production pins, or release artifacts
were changed. This tested the real application, not a minimal template.

The official Linux release manifest still selected these SDKs. Both downloaded
archive SHA256 values matched the manifest:

| Input | Stable | Beta |
| --- | --- | --- |
| Flutter | 3.50.0 | 3.51.0-0.1.pre |
| Dart | 3.14.0 | 3.15.0-118.1.beta |
| Framework | `ab2912035e160d9cad6306df307576da6128ebdb` | `d040ef5c5c4c8be0948207fadd35e87305920146` |
| Engine | `371f77202a73e8dff57a8b3bff75bca55c090aee` | `e98d27d956eb75479e4677bcc651a3d8f0b7eb91` |
| SDK archive SHA256 | `6ea2d806fd57269ae783e6788e2a81fc26eaad782f1e0d0ff38623bb765ff9f5` | `e0470b8f29693a2b2a4fc2bb16c170a286079217c8800ae5efa2625bfb7b0ecd` |
| Official debug engine SHA256 | `f38c8d6a0ef588b58daccdecaf2000f5cbdad267979369560c347a40af3eb258` | `6c94b48502f98b5b69a3dc2dde48e56419bf69677718c04e616a22b4664dc614` |

Exact `fl_task_runner.cc` source confirms that beta includes PR 194525's single
source and lifetime fix; stable does not. Renderer PR 193533 remains open. The
task-runner fix alone does not establish renderer shutdown synchronization.
Beta's `flutter pub get --enforce-lockfile` exited 65: its SDK requires `test`
1.33.0, `test_api` 0.7.15, and `test_core` 0.6.21. Ordinary `flutter pub get`
resolved only those three version changes in the disposable beta copies.

| Environment and normal close route | Stable result | Beta result |
| --- | --- | --- |
| Ubuntu 22.04.5, private Xvfb/Openbox, `flutter run -d linux --no-pub`, WM close | CLI exit 0; native exit not independently observed | Same |
| Same Ubuntu environment, debug bundle executable, ten fresh processes, `wmctrl -ic` | Native exits `0,0,0,0,0,0,0,0,0,0` | Native exits `0,0,0,0,0,0,0,0,0,0` |
| NixOS/KDE Wayland, project `nix develop`, `flutter run`, KWin close | Five native exits 0 | Not run: official beta archive failed to link |
| Same host, `GDK_BACKEND=x11` through XWayland | Native exits `0,0,0`, then SIGSEGV (11; shell convention 139); loop stopped | Same build blocker |

Ubuntu used the same existing container image
`sha256:da06da12a98209869e0d5bb0c656bea9d44ca4207f1d2508a0bf64bce3cc338b`
for both SDKs: GTK 3.24.33, GLib 2.72.4, libc 2.35-0ubuntu3.18, Mesa 23.2.1,
and LLVM 15.0.7. Logs identify Impeller OpenGLESSDF; process maps confirm
`swrast_dri.so` and `libLLVM-15.so.1`. Both candidates logged OpenGL frame-size
timeouts. No critical errors appeared in their app logs. Windows mapped and
advertised `WM_DELETE_WINDOW`; no screenshot or Dashboard-content assertion was
captured. These are bounded close results, not visual or package acceptance.

The host used KDE/KWin 6.8.3, Mesa 26.3.0, and the Radeon 780M desktop renderer.
Its stable SDK came from the committed Nix environment, not the inherited
3.47.9 shell command. `strace -f -e trace=process` recorded native exit status
independently of Flutter's CLI, which also returned 0 for the crash. All host
launches logged an ATK critical. The failing close additionally logged invalid
GTK/GDK widget/window assertions. Its core and all-thread GDB trace show the
main thread in `gdk_window_get_type_hint`, called by
`yaru_window_get_state(window=0x0)` in `yaru_window_linux` 0.2.2
(`lllf-b68.4.1`). This is not the
historical Mesa raster-thread stack and does not prove a task-runner failure.

The host beta command `flutter build linux --debug --no-pub`, inside the same
project shell, exited 1 with unresolved native-library link dependencies,
including epoxy, Wayland, and fontconfig; pkg-config also reported missing
`sysprof-capture-4`. No SDK patch or compatibility launcher was added to bypass
that blocker. Beta's native Wayland/XWayland behavior remains unverified.

Commands, orchestration scripts, SDK/build/bundle checksums, lockfile differences,
per-close process maps and logs, and the host core/backtrace remain under
`/tmp/opencode/beta-shutdown-evidence/`. The Ubuntu commands were
`flutter pub get`, `flutter build linux --debug --no-pub`,
`flutter run -d linux --no-pub`, and
`build/linux/x64/debug/bundle/legion_frontend`; `wmctrl -ic` requested normal WM
close. Host runs used the same `flutter run` command with `-v` for diagnostics
and PID-qualified `kdotool windowclose`. No app was signalled to count a close.
Two earlier host automation attempts ended on CLI stdin EOF with SIGTERM; they
were excluded. Keeping the CLI input open corrected the test setup.

No release-mode, AppImage, Debian, Nix package, authorization, hardware readback,
restoration, or helper-cleanup qualification ran. Keep production on stable with
engine retention; this result changes neither the deployment decision nor the
known-failure assertions.

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
