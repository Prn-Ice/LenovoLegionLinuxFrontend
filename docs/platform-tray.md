# Tray icon

The tray code is implemented but not connected to the app yet. The desktop draws
the menu, and the adapter uses the generic `computer` icon.

## Usage

- Create one `PlatformTray(DBusTrayTransport())` for the app. Call `start()` once,
  update it with `updateMenu`, and await `dispose()` at shutdown.
- `TrayRegistration.registered` means the watcher accepted registration. It does
  not guarantee a host or visible icon. Do not enable minimize-to-tray based on
  registration alone.
- Watcher owner changes trigger re-registration; stale completions are ignored.
  Opening or registration failures report unavailable.
- After a session-bus connection failure, create a new adapter. The app must also
  retry registration failures when the watcher has not changed.

## Menu requirements

`TrayMenuItem` supplies:

- A stable, positive, unique ID, label, and enabled state.
- An optional `radio`/`checkmark` toggle type and nullable checked state. Unknown
  checked state has no toggle marker.
- Nested children and an optional activation callback.

Events invoke only enabled items. Build the menu from confirmed feature state and
capabilities. On activation, recheck whether the action is supported and busy,
then use the existing confirmation, Polkit, and readback flow. Do not add
privileged tray actions until confirmation works with the main window hidden.

The initial menu contains only a disabled “Status unavailable” item.

## D-Bus interface

The adapter exports `org.kde.StatusNotifierItem` at `/StatusNotifierItem` and
`com.canonical.dbusmenu` at `/MenuBar` on a dedicated session-bus connection.

References: [Status Notifier Item specification](https://specifications.freedesktop.org/status-notifier-item/latest-single),
[DBusMenu interface](https://github.com/Alexays/Waybar/blob/master/protocol/dbus-menu.xml).

## Not implemented

- Full DBusMenu protocol and introspection coverage.
- A packaged Legion icon.
- App state and actions: Open, Quit, hide, hardware actions, and settings toggles.
- Window recovery.
- Automatic transport reconnection.

## Not tested on a desktop

- Actual watchers, hosts, and menus on X11 and Wayland.
- Hardware, Polkit, and application-lifecycle behavior; private-bus tests do not
  verify these.
