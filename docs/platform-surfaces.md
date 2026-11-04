# Platform surfaces integration

Phase 7 provides an isolated `PlatformOsd` and typed `PlatformEvent` values.
Neither is wired to feature transitions or a native window. They do not emit
notifications or change hardware. The follow-ups below are open, not promises
of current functionality.

## OSD — lllf-cqn.7.1

Use `lib/features/platform_surfaces/widgets/platform_osd.dart` for confirmed
power mode, keyboard brightness, fan boost and automation changes. A future
owner must connect actual feature transitions and preferences, and implement
the transparent, non-activating desktop window in `linux/runner/my_application.cc`
or a suitable native integration. Define placement, timeout (the handoff suggests
about two seconds), replacement, lifecycle and reduced motion; test X11 and
Wayland separately. Do not confuse an attempted command with readback. OSD is
for desktop/hotkey feedback, not a substitute for the app's modal error policy.

## Tray — lllf-cqn.7.2

Expose a StatusNotifierItem and native desktop menu, not a Flutter imitation of
Plasma chrome. The handoff calls for a Legion icon and a status summary followed
by a radio group for supported power modes; fan boost and battery health toggles;
a keyboard-light submenu; then Open Legion and Quit. Derive checked/enabled
states from existing feature snapshots and capabilities, show unknown honestly,
and disable unavailable or busy actions. Preserve the existing authorization,
confirmation and readback flows; a tray click must not bypass Polkit or the
backend allow-list. Determine how confirmation works when the main window is
hidden before enabling a privileged action. Let the desktop theme menu selection
and chrome; app accent belongs only in suitable icon artwork. Account for absent
watchers, reconnection, startup and teardown. No tray is currently registered.

## Notifications — lllf-cqn.7.3

`lib/features/platform_surfaces/models/platform_event.dart` describes confirmed
changes without coupling the producer to a transport. A future adapter can map
these to `org.freedesktop.Notifications` on the session bus. Handle unavailable
servers and reconnect/disposal, escape untrusted strings as required by the
protocol, respect preferences and avoid duplicate routine success notices when
the result is already visible. Keep error recovery in the app's established
modal dialog, not a desktop notification. Notification actions such as Undo
must not be offered unless a safe, confirmed operation exists. No event producer
or desktop notification transport is currently wired.

Widget tests are not evidence of native desktop behavior or visual review.
