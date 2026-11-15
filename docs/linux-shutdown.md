# Linux shutdown qualification

Flutter 3.50.0 remains the SDK target. Desktop shutdown qualification is
incomplete, tracked in `lllf-dt0.5.16`. The user chose to keep the latest Flutter
and document this issue if a clean fix was unavailable.

## What fails

Closing the app can crash the process. In the NixOS AppImage VM, the main thread
reaches process exit while Flutter's raster thread still calls Mesa's
`glReadPixels`. Mesa can then free resources that the raster thread still uses.
This is separate from temporary-helper authentication cancellation.

Explicitly destroying the retained window after the application loop stops also
failed. GTK destroys Flutter's renderer while its frame mutex can still be in
use, producing `g_mutex_clear() called on uninitialised or locked mutex`. Completing
queued main-context work did not prevent that failure. These experiments were
removed; they are not release fixes.

## Evidence

| Candidate | Result |
| --- | --- |
| Flutter 3.47.9, commit `3cf5fdc` | NixOS AppImage crashed on its first Settings close in Mesa readback. |
| Flutter 3.50.0 / Yaru 12, commit `adab917` | The same NixOS close failure; Ubuntu AppImage launch/close and Debian installation checks passed. |
| Experimental native cleanup, commit `966154c` | NixOS AppImage and Debian 12 aborted during normal window close. The experiment was reverted in `1db619b`. |

Local packages, source manifests, and logs are retained under
`build/qualification/adab917/rejected-shutdown/` and
`build/qualification/966154c/rejected-shutdown/`. Each directory records its
rejected status. Neither candidate replaced `build/legion-frontend.AppImage`.

The SDK upgrade passed generation, analysis, 777 Flutter tests, 24 visual
renders, 14 native app journeys and both restart phases, four native codec tests,
and the Nix package/source check. Those results do not establish clean shutdown
for every package and graphics environment. The user's KDE Wayland/hybrid
approval-cancel-retry test still needs a replacement image.

## Upstream work

Flutter's [renderer lifetime work](https://github.com/flutter/flutter/pull/193533)
proposes moving mutex and task-runner cleanup until raster references are gone
and synchronizing graphics-resource teardown. It remains open and is not in
Flutter 3.50.0. Related
[deferred window destruction work](https://github.com/flutter/flutter/pull/193126)
addresses teardown during nested GTK drawing. Our traces match these failure
classes; those proposals have not been tested as fixes for this app.

The separate [task-runner fix](https://github.com/flutter/flutter/pull/194525)
was merged upstream but is absent from the exact 3.50.0 engine revision
`371f77202a73e8dff57a8b3bff75bca55c090aee`. Keep the existing approved engine
retention until a compatible fix passes repeated-close checks
(`lllf-dt0.5.13`).

## Resume qualification

Test a supported stable SDK containing the relevant fixes, or a safe app-level
mitigation, with the standard launch commands. Require repeated X11 and Wayland
window closes, exit status zero, and no GLib/GObject critical errors. Then test
password cancellation, an explicit approved retry in the same process, hardware
readback, restoration, and helper cleanup.

The tag workflow continues to require successful package acceptance. A failed
close check stops release preparation. No release tag or GitHub release was
created during this investigation.
