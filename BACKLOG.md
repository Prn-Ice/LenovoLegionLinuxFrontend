# Community backlog

Last reviewed: **2026-11-04**. This is a manually maintained summary of current
work, not a release schedule or a promise that every item will ship. Update it
when priorities, feature readiness, or hardware evidence change.

For what already exists, see [feature readiness](README.md#features-and-readiness).
Development and hardware testing currently use **one physical laptop: Legion
Slim 7 16APH8 (82Y4, BIOS M1CN48WW)**. Some features remain unverified on it;
other models are unverified. Automated tests and synthetic hardware samples do
not establish real-device support.

## In progress

- **Fan curves:** finish driver support for truthful curve readings on the test
  device, then verify applying a curve, reading it back, and restoring it.
  Working fan RPM readings do not prove curve control works.
- **Graphics modes:** finish deploying and validating guarded next-boot graphics
  selection. Complete external-display, reboot, hibernation, and recovery checks.
  Hybrid Auto remains unavailable as a desktop action because unplugging AC can
  detach the GPU while applications still use it.
- **Suspend and hibernation reliability:** investigate the perceived Hybrid
  suspend-to-hibernate hang, validate the suspend-to-hibernate guard, and resolve
  remaining Wi-Fi restore timeouts and NVIDIA firmware-query errors.

## Next work

- **Reliable battery feedback:** refresh Battery state after conservation changes
  on the Dashboard. Until fixed, use the Battery page's Refresh action if it
  shows the previous value.
- **Safe power defaults:** obtain complete firmware-backed defaults before
  offering restoration. Current readings and recorded reference values are not
  factory defaults; the GPU power-boost default is still unresolved.
- **Native Linux app tests:** expand the current Battery health journey to
  lighting/profile persistence, automation, power, fans, graphics, navigation,
  diagnostics, cancellation, and error recovery. Use a safe test backend rather
  than changing the host's hardware or user data.
- **Desktop integration:** connect the existing tray, on-screen display, and
  notification components to confirmed app state and actions. The components
  exist, but are not connected to the app yet.

## Further backlog

- Make GPU process/PCI actions safe in the privileged backend before enabling
  them; reject changed targets rather than acting on stale process lists.
- Finish graphics boot-reconciliation packaging and investigate legitimate
  Hybrid clients being rejected after hibernation.
- Polish keyboard automation layout and verify guidance contrast in light mode;
  retire legacy manual accent preferences.
- Record additional model/BIOS and keyboard evidence, including separate reading
  and writing results. Do not infer support from a similar model name.
- Finish release-source provenance records, recheck blocked dependency upgrades,
  and resolve vendor-logo/reference-image permissions.
- Investigate the PipeWire crash observed during Plasma logout.

## Help test another device

Open a [GitHub issue](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/issues)
with your model, BIOS, kernel, driver/CLI versions, and what you actually tested.
The [model-support guide](docs/model-support.md) explains how to copy a read-only
diagnostic report and remove personal information. Report readings separately
from changes you applied and checked on the hardware. A diagnostic report alone
does not verify writes; you do not need to perform risky changes to contribute.

Maintainers use Beads for detailed tasks and investigation notes. This backlog
and the README are the public summary; community members do not need Beads to
follow progress or report problems.
