# Platform surfaces

`lib/features/platform_surfaces/` contains presentation components and native
adapters. They are **not connected to app-lifetime feature producers or user
preferences**. They do not currently enable a tray, automatic OSD, or desktop
notifications.

| Component | Implemented boundary | Limits |
| --- | --- | --- |
| `PlatformEvent` / `PlatformOsd` | Typed confirmed-change values and a Flutter OSD widget | No automatic feature-state connection |
| [Native OSD](platform-osd.md) | MethodChannel and lazy X11 GTK popup | Channel registered; Wayland unavailable; not Flutter visual parity |
| [Tray](platform-tray.md) | StatusNotifierItem and partial DBusMenu transport | No app registration, state menu, or actions wired |
| [Notifications](platform-notifications.md) | Session-bus transport and confirmed-state observers | No global listeners or persisted preference wired |

Adapters present confirmed results; they do not authorize hardware changes.
Any caller must preserve the existing confirmation, Polkit, backend validation,
and readback flow. Initial loads, attempted writes, and unknown values must not
be reported as successful changes. Errors follow the
[error and feedback standard](error-and-feedback-standard.md).

Hardware-free tests cover adapter contracts and lifecycle. They do not prove
desktop focus, placement, menu appearance, accessibility, or compositor behavior.
