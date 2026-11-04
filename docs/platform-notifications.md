# Desktop notifications

The native adapter is implemented, but is **not wired globally**. Construction is
lazy: it does not contact the host. Tests inject a fake `DBusClient`; they never
notify the developer's desktop or access hardware.

## Caller contract

`ConfirmedPlatformChanges.observePower` and `observeFans` accept feature states
and return confirmed change events. `DesktopNotifications.show` accepts an
event plus `enabled` and `resultVisible` inputs; no appearance setting is wired
to these inputs. Until preferences finish loading, callers must pass false.
Visibility must include both the current route and whether the window is visible; if
unknown, conservatively pass true. Keep feeding baseline observers even when
notifications are disabled or the page is visible, so enabling notifications
does not replay old changes. Dispose the service once using `close()`; providers
may register asynchronous service cleanup, not a second Bloc cleanup.

`show` defaults to disabled and visible. Delivery results are `sent`, `suppressed`,
`unavailable`, or `disposed`; unavailable feedback does not fail the hardware
operation and must not open another modal. Existing feature errors stay in the
app's established modal error flow.

## Confirmed sources and limitations

- Power: `PowerBloc._reloadState` applies `PowerRepository.loadSnapshot()`;
  observe stable, non-error `currentMode` changes, not request or notice strings.
- Fan boost: `FansBloc._reloadState` applies `FansRepository.loadSnapshot()`;
  observe stable, non-error `maximumFanSpeedEnabled` changes.
- The observers suppress initial/unknown values, loading/applying states and
  errors, retaining the last stable baseline during a write. They can report
  externally observed/polled changes too. They do not start the feature Blocs.
- Lighting currently exposes white-backlight on/off, not a confirmed brightness
  fraction. No brightness producer is provided.
- Automation `lastRunSummary` combines completed, skipped and failed actions,
  including arbitrary external commands. It is not a safe blanket confirmed
  event source. A future producer must emit specific verified outcomes.

No app listener or persisted preference currently connects these adapters.

## Protocol and ownership

`org.freedesktop.Notifications.Notify` runs only on the session bus, using
signature `susssasa{sv}i` and reply `u`. Bodies are escaped as notification markup;
summaries are fixed plain text. No actions, Undo, privileged operations or
error notifications are offered. Expiration requests four seconds (the desktop
server decides actual presentation). IDs replace the previous notification of
the same event kind. Every send resolves the server's unique owner, clearing IDs
on owner change and avoiding accidental reuse across desktop-server restarts.
No absent server is auto-started. Failures reset/close the owned connection;
the next event retries lazily. Close is idempotent and waits for pending work.

The client factory transfers ownership: return a fresh client, not a shared one.
Concurrent sends are ordered. Disposal releases adapter waits using a local
signal, detaches/closes the client, then drains queued work. Resolved dbus 0.8.0
closes the socket but does not complete outstanding method completers; no remote
reply is needed to dispose this adapter. Late transport errors remain observed,
and the detached client is not closed twice by the failure handler.

Unit tests verify the wire mapping, not a real notification daemon,
desktop appearance, Wayland/X11 behavior or packaged app identity.
