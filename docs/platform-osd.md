# Native OSD boundary

`NativeOsd` is a presentation-only typed MethodChannel client. The Linux runner
registers its handler beside (not instead of) the existing plugin registration.
There is no second Flutter engine, hardware access, startup popup, or change to
main-window close behavior. A single GTK popup is created only on first delivery.

## Capability and appearance

- **X11 only:** a non-activating `GTK_WINDOW_POPUP`, no focus/present calls,
  notification hint, no taskbar/pager entry, empty input shape. Placement is
  bottom-center of the main window's monitor work area with a 48 logical-pixel
  inset. It does not claim to follow the currently focused application's monitor.
- **Wayland:** explicitly unavailable. GTK3 alone cannot guarantee global
  placement/stacking; no layer-shell dependency is installed. Do not advertise
  desktop OSD support there until a compositor-compatible host is implemented.
- Native GTK `.osd` theme colors and typography render the same event labels as
  `PlatformOsd`. This is **not** a Flutter-rendered `PlatformOsd` window: its icon,
  accent, progress bar and exact Flutter surface are not reproduced. The native
  surface requests an RGBA visual and rounded theme background; transparent
  corners depend on an X11 compositing manager (opaque fallback otherwise).
  A separate engine just to reuse that widget would add substantial lifetime and
  theme synchronization complexity. Full visual integration remains open.
- No animations; reduced-motion users receive the same instant replacement.
  Labels are plain text, never markup; external text is bounded to 240 runes.

The default lifetime is two seconds, bounded on both sides to 500–5000 ms. Each
show replaces the existing content and cancels/restarts the native timer. Hide
cancels it. The view owns the channel/host; destruction removes its handler,
cancels the timer, destroys the popup and releases the channel. The popup is not
an application window and cannot keep the app alive after the main window closes.

## Caller contract (not integrated)

`NativeOsd.showConfirmed` accepts an event, `enabled`, and `mainWindowVisible`.
No app preference or visibility source is connected to those inputs. One
app-lifetime owner must dispose the adapter and call `hide()` when disabling
feedback or revealing the main window.

Only a **changed**, completed authoritative snapshot is valid, not initial load,
refresh, an attempted command or a failed write. Supported event inputs are
power mode, keyboard brightness (0–1), fan boost and completed automation.
Unknown values are suppressed. The caller owns deduplication and the live
preference/visibility sources. Keep ordinary visible-page success in its updated
control; errors still use the existing modal error flow. An unavailable OSD is
not a failed hardware operation and must not manufacture a success notification.

## Verification limits

Fake-channel tests cover content, preferences/foreground suppression, unknown
values, bounded duration, replacement calls, missing/failed transports, native
unsupported response and idempotent disposal. Native compilation is a separate
gate. These tests cannot prove window-manager focus, placement, timer replacement
or screen-reader behavior. No popup was launched on the development host.

App producers and preferences remain unconnected. Real-desktop X11 focus,
click-through, timer/replacement, shutdown, and accessibility remain unverified.
Transparent Flutter visual parity and Wayland hosting are unimplemented.
