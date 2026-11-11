# Desktop notifications

The notification code is implemented but not connected to the app yet. It
connects to D-Bus only when needed. Tests use a fake `DBusClient` and do not send
desktop notifications or access hardware.

## Usage

`ConfirmedPlatformChanges.observePower` and `observeFans` accept feature states
and return confirmed change events. `DesktopNotifications.show` accepts an
event plus `enabled` and `resultVisible` inputs. Defaults are `enabled: false`
and `resultVisible: true`.

- Keep notifications disabled (`enabled: false`) until preferences have loaded.
- Set `resultVisible` to true when both the result's page and the window are
  visible. If visibility is unknown, pass true to suppress the notification.
- Keep updating the observers while notifications are suppressed, so enabling
  them does not announce old changes.
- Call `close()` once at shutdown. A provider may register asynchronous service
  cleanup, but must not close the Bloc again.
- If notifications are unavailable, leave the hardware result unchanged and do
  not open an error dialog. Keep feature errors in the existing modal error flow.

Delivery results are `sent`, `suppressed`, `unavailable`, or `disposed`.

## Supported events

- Power: `PowerBloc._reloadState` applies `PowerRepository.loadSnapshot()`;
  observe stable, non-error `currentMode` changes, not request or notice strings.
- Fan boost: `FansBloc._reloadState` applies `FansRepository.loadSnapshot()`;
  observe stable, non-error `maximumFanSpeedEnabled` changes.
- Observers emit no events for initial or unknown values, loading, pending
  changes, or errors. Initial values establish the baseline; unknown values reset
  it. During a write, observers keep the last confirmed value. They can detect
  changes made by other tools through polling. They do not start the feature Blocs.
- Lighting currently exposes white-backlight on/off, not a confirmed brightness
  fraction. No brightness producer is provided.
- Saving a keyboard-profile assignment does not confirm that the profile was
  applied. Add automation notification events only after a confirmed lighting
  result.

## D-Bus details and cleanup

`org.freedesktop.Notifications.Notify` runs only on the session bus, using
signature `susssasa{sv}i` and reply `u`. Bodies are escaped as notification markup;
summaries are fixed plain text. The service offers no actions, Undo, privileged
operations, or error notifications. The expiration request specifies four seconds;
the desktop server determines actual presentation.

The adapter passes the previous notification ID to replace a notification of the
same kind. Every send resolves the server's unique owner and clears IDs on owner
change, preventing reuse across server restarts. The adapter does not start a
notification server.

The client factory must return a new client. The adapter owns and closes it.
Failures reset and close the connection; the next event retries lazily.
Concurrent sends are ordered.

`close()` is idempotent. It releases adapter waits using a local signal, detaches
and closes the client, then drains queued work. Resolved dbus 0.8.0 closes the
socket but does not complete outstanding method completers. Disposal therefore
does not wait for a remote reply. Late transport errors remain observed, and the
failure handler does not close the detached client twice.

## Testing

Unit tests verify the D-Bus mapping. Notification delivery through a real daemon,
desktop appearance, Wayland/X11 behavior, and packaged app identity still need
manual testing.
