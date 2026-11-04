# Native on-screen display

`NativeOsd` sends display events to a GTK popup through a typed MethodChannel.
The popup is created when first needed. It is not connected to app events or
preferences yet.

## Supported desktops and appearance

- **X11:** the popup appears at the bottom-center of the main window's monitor
  work area, with a 48 logical-pixel inset.
- **Wayland is not supported.** GTK3 cannot reliably position the popup above
  other windows; no layer-shell dependency is installed.
- The GTK popup uses the same labels as `PlatformOsd`, but not its icons, accent,
  progress bar, or exact Flutter appearance. It uses native GTK `.osd` colors and
  typography. Transparent corners require an X11 compositing manager; otherwise
  the background is opaque.
- Content changes instantly, without animation, including with reduced motion.

The popup stays visible for two seconds by default. Durations are limited to
500–5000 ms. Each show replaces the content and restarts the timer.

## Usage

`NativeOsd.showConfirmed` accepts an event, `enabled`, `mainWindowVisible`, and
an optional `duration`.

- Create one adapter for the app and call `dispose()` at shutdown. Call `hide()`
  when disabling feedback or revealing the main window.
- Show the popup only after a confirmed setting changes or automation completes
  with a verified result. Do not show it for initial readings, refreshes, pending
  changes, or failures.
- Supported events are power mode, keyboard brightness (0–1), fan boost, and
  completed automation. Unknown values are suppressed.
- Prevent duplicate events and supply the current preference and window
  visibility. Delivery is suppressed when disabled or the main window is visible.
- Show visible-page success in the updated control. Keep errors in the existing
  modal error flow.
- If the popup is unavailable, do not report the hardware operation as failed or
  show a replacement notification.

## Technical details

- The Linux runner registers the handler alongside the existing plugins. It
  uses no second Flutter engine, accesses no hardware, and shows no startup popup.
- A single non-activating `GTK_WINDOW_POPUP` uses a notification hint, no
  taskbar/pager entry, and an empty input shape. It makes no focus/present calls.
- Rendering requests an RGBA visual and rounded theme background. Labels are
  plain text, never markup; external text is limited to 240 runes.
- Show cancels the previous native timer before starting another; hide cancels it.
- The view owns the channel and host. Destruction removes the handler, cancels
  the timer, destroys the popup, and releases the channel.
- Main-window close behavior is unchanged. The popup is not an application window
  and cannot keep the app alive after the main window closes.

## Testing

Fake-channel tests cover content, preference/foreground suppression, unknown
values, bounded duration, replacement calls, missing/failed transports,
unsupported native responses, and idempotent disposal. Native compilation needs
a separate check.

Still to test on X11: appearance, placement, focus, click-through, replacement
timing, shutdown, and accessibility.
