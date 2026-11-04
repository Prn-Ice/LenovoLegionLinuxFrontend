# Native tray adapter handoff

This is an unwired foundation, not an enabled application feature. The adapter
exports `org.kde.StatusNotifierItem` at `/StatusNotifierItem` and a
`com.canonical.dbusmenu` object at `/MenuBar` on a dedicated session-bus
connection. The desktop owns the menu presentation. It uses the generic
`computer` icon until a packaged Legion icon is available.

Create `PlatformTray(DBusTrayTransport())` in the eventual application-lifetime
owner, call `start()` once, publish snapshots with `updateMenu`, and await
`dispose()` at teardown. `TrayRegistration.registered` means only that the
watcher accepted registration; it does not establish a host is present or an
icon is visible. Never use it alone to enable minimize-to-tray. Watcher owner
changes trigger re-registration; stale registration completions are ignored.
An opening or registration failure reports unavailable. A lost session-bus
connection is not automatically reconnected: recreate the adapter after a
transport failure. Registration failure without an owner change also needs an
explicit retry strategy before integration.

`TrayMenuItem` supplies stable positive unique IDs, label, enabled state,
optional `radio`/`checkmark` and nullable checked state, nested children, and
an optional activation callback. An unknown checked state has no toggle marker.
Events invoke only enabled items. The owner must derive state and capabilities
from confirmed feature snapshots, recheck busy/capability state on activation,
and route commands through existing confirmation, Polkit and readback flows.
Callbacks must not expose privileged writes before hidden-window confirmation
is designed. The initial menu contains only a disabled unavailable status;
no Open, Quit, hide, hardware action, or settings toggle is wired here.

Before shipping, complete the DBusMenu protocol and introspection coverage for
the desktops being supported, package the icon, connect state and safe actions,
define window recovery/teardown and retry/reconnect policy, and validate actual
watchers, hosts and menus on both X11 and Wayland. The private-bus tests are not
desktop, hardware, Polkit, or lifecycle validation.

References: [Status Notifier Item specification](https://specifications.freedesktop.org/status-notifier-item/latest-single),
[DBusMenu interface](https://github.com/Alexays/Waybar/blob/master/protocol/dbus-menu.xml).
