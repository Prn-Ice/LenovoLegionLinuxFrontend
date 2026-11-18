# Linux window preview

A standalone preview of Flutter's experimental Linux window API, using the
frontend's Yaru controls and balanced-mode colors. It reads native window state
and offers maximize, fullscreen, restore, move, resize, and appearance controls.
It does not access laptop hardware or application settings.

## Run

Use a separate Flutter main/master checkout. The API is gated to that channel;
having its source in stable 3.50 does not make it available there. This preview
uses Flutter revision `7f49251bab097db33a35967aa5af561f29c63db2` and Dart
`3.15.0-154.0.dev`.

From this directory, with that SDK on `PATH` and Linux build dependencies loaded:

```sh
flutter config --enable-windowing
flutter pub get --enforce-lockfile
flutter analyze
flutter run -d linux
```

For this session, the checkout is `/tmp/opencode/lllf-window-sdk`. From the
repository root:

```sh
nix-shell experiments/linux_window/shell.nix
export FLUTTER_ROOT=/tmp/opencode/lllf-window-sdk
export PATH="$FLUTTER_ROOT/bin:$PATH"
export HOME=/tmp/opencode/lllf-window-home
export PUB_CACHE=/home/prnice/.pub-cache
cd experiments/linux_window
flutter run -d linux
```

The separate home keeps the experimental feature flag out of the user's Flutter
configuration. The production SDK pin and app window integration are unchanged.
The preview shell adds the upstream engine's shared-library dependencies. The
production shell normally gets these paths through Nix's packaged Flutter SDK.
After changing that shell, run `flutter clean` and
`flutter pub get --enforce-lockfile` before rebuilding so CMake drops old library
paths.

## Evaluation result

**Keep the production window integration.** The preview builds and runs, but it
has not established a clean replacement on KDE Wayland.

Checked on 18 November 2026 with the SDK revision above, Impeller, and the user's
KDE Wayland session with Karousel enabled. The native runner comes from
`flutter create --platforms=linux`; it has no app-specific native changes.

| Check | Result |
| --- | --- |
| Preview analysis and Linux debug build | Passed. |
| Root application analysis on stable | Passed. |
| Standard `flutter run -d linux --no-pub` | Built and opened the preview. |
| Startup | The initial 1 px surface caused a layout overflow. Deferring the content until a size notification removed that overflow; a native subsurface-frame timeout remains. |
| Restored window | Yaru content rendered, but KDE still added a title bar despite `decorated: false`. |
| Maximize and restore | Compositor-driven transitions updated the displayed state and switched between square and rounded clipping. |
| Fullscreen | The displayed state changed, but the capture retained a narrow surface. Reliable screen-filling geometry remains unverified. |
| Corner transparency | The clip is visible; the extra native decoration prevents this capture from proving the intended all-corner transparency. |

![Preview after restoring](evidence/restored.png)

The desktop compositor chose the restored dimensions (880 × 1041 logical content
pixels), rather than the requested 880 × 620. Screenshots show the actual window;
they are not mockups. The capture predates the copy correction from
"with a transparent native background" to "native transparency requested": the
API request does not establish the rendered result. Local logs and captures are in
`/tmp/opencode/lllf-window-evidence`.

The final run still logged ATK embedding criticals, cursor-theme messages, and:

```text
Timed out waiting for subsurface frame of size 1760x1240 (have 0x0)
```

The visual pass covered system-dark appearance and compositor-driven state
changes. Light appearance, every in-app button and shortcut, drag/resize gestures,
compact layout, startup frame timing, other desktops, and packaged launches remain
unverified. No automated test suite was added to this diagnostic package.

The extra title bar also appeared when calling `setDecorated(false)` after the
generic `WindowController` constructor. Creating `WindowControllerLinux` with
`decorated: false` did not resolve it. The cause has not been isolated between
the experimental API, GTK, and this desktop configuration.

## What to inspect

- Start the preview: one visible window should appear with its content ready.
- Inspect all four restored corners in light and dark modes: the clipped area
  should reveal the desktop rather than a black or opaque rectangle.
- Maximize: the window should fill the usable desktop with square corners.
- Enter fullscreen: the surface should fill the screen. Press Escape to leave.
- Restore: the previous window size and rounded corners should return.
- Drag the title bar and each edge: the compositor should move or resize the
  window. Resize to 420 × 500: actions should remain reachable by scrolling.

The preview still clips its Flutter surface to an 8 px radius. The new API
supplies native transparency and window operations; it does not automatically
draw Yaru decorations, corners, shadows, or resize borders. Production adoption
requires evidence from the full app and its packaged launch flows.

Sources: [Flutter's window API guide](https://docs.flutter.dev/blog/desktop-windowing-apis)
and the [Linux implementation at the tested revision](https://github.com/flutter/flutter/blob/7f49251bab097db33a35967aa5af561f29c63db2/packages/flutter/lib/src/widgets/_window_linux.dart).
