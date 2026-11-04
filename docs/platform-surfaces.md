# Desktop integrations

`lib/features/platform_surfaces/` contains code for a tray icon, on-screen display
(OSD), and desktop notifications. These are not connected to the app yet.

| Component | Implemented | Limits |
| --- | --- | --- |
| `PlatformEvent` / `PlatformOsd` | Change-event types and a Flutter OSD widget | No automatic feature-state connection |
| [Native OSD](platform-osd.md) | MethodChannel and lazy GTK popup | X11 only; appearance differs from the Flutter widget |
| [Tray](platform-tray.md) | StatusNotifierItem and partial DBusMenu transport | Not connected to app state or actions |
| [Notifications](platform-notifications.md) | Session-bus transport and confirmed-state observers | Not connected to app events or saved preferences |

## Requirements

- Use these integrations to show confirmed changes. They do not authorize
  hardware changes.
- Send actions through the existing confirmation, Polkit, backend validation,
  and readback flow.
- Do not announce initial readings, pending changes, or unknown values as successes.
- Follow the [error and feedback standard](error-and-feedback-standard.md).

Automated tests cover behavior and cleanup without hardware. Desktop appearance,
focus, placement, accessibility, and compositor behavior still need manual testing.
