# Third-party notices

The application is licensed under `GPL-2.0-or-later`; see [README.md](README.md#license)
and [LICENSE](LICENSE). Third-party materials retain their own notices and terms.

## OpenRGB Spectrum ports

Primary source: [OpenRGB](https://github.com/CalcProgrammer1/OpenRGB), verified
2026-11-04 at commit `fc3aa07947e82da060a429e0b4b10886c7e0d697`.
This is the revision checked for attribution. The original port's upstream
revision is unknown.

| Local file | Upstream source at the verified commit |
| --- | --- |
| `lib/features/lighting/models/spectrum_led_map.dart` | [`Controllers/LenovoControllers/LenovoDevices.h`](https://github.com/CalcProgrammer1/OpenRGB/blob/fc3aa07947e82da060a429e0b4b10886c7e0d697/Controllers/LenovoControllers/LenovoDevices.h), `legion7_gen7and8_ansi_leds` and `legion7_gen7and8_neon_leds` |
| `lib/features/lighting/services/spectrum_protocol.dart` | [`LenovoUSBController_Gen7_8.cpp`](https://github.com/CalcProgrammer1/OpenRGB/blob/fc3aa07947e82da060a429e0b4b10886c7e0d697/Controllers/LenovoControllers/LenovoUSBController_Gen7_8/LenovoUSBController_Gen7_8.cpp) and [its header](https://github.com/CalcProgrammer1/OpenRGB/blob/fc3aa07947e82da060a429e0b4b10886c7e0d697/Controllers/LenovoControllers/LenovoUSBController_Gen7_8/LenovoUSBController_Gen7_8.h) |

All three upstream files declare `GPL-2.0-or-later`. The `LenovoDevices.h`
header credits Cooper Hall (geobot19), 17 Apr 2022. OpenRGB's
[LICENSE](https://github.com/CalcProgrammer1/OpenRGB/blob/fc3aa07947e82da060a429e0b4b10886c7e0d697/LICENSE)
contains the GNU GPL version 2 text; the file-level declarations grant the
option of later versions.

The Dart ports were modified locally. Git history records the Gen 7/8 encoder
port (`ac37a83`) and the LED-table port (`df37f3a`) on 2026-06-22. The map converts
upstream LED entries into name/value pairs.
The encoder ports packet construction from the C++ HID driver; local changes
include power limiting, white balance, and protocol updates through 2026-08-29
(`21ceffa`). Attribution notices were added on 2026-11-04 without changing behavior.

History does not record an upstream checkout hash. A dated comparison found the
three files above byte-identical at pre-port commit
[`a8a97fa38d103d4aaba75c815f87522603a5c0fb`](https://github.com/CalcProgrammer1/OpenRGB/commit/a8a97fa38d103d4aaba75c815f87522603a5c0fb)
(2026-03-17). The original map's 111 name/value pairs exactly match its ANSI and
neon tables joined with
[`RGBControllerKeyNames.cpp`](https://github.com/CalcProgrammer1/OpenRGB/blob/a8a97fa38d103d4aaba75c815f87522603a5c0fb/RGBController/RGBControllerKeyNames.cpp),
credited to Chris M (Dr_No), 25 Jan 2022, `GPL-2.0-or-later`.

## Assets and fonts

- `assets/gpu_vendors/{amd,intel,nvidia}.svg`: the
  [asset README](assets/gpu_vendors/README.md) records retrieval from Simple Icons
  on 2026-08-30, its CC0 1.0 project license, and separate brand/trademark caveats.
- The release font manifest contains Google's Material Icons (the Flutter 3.47.9
  SDK's `MaterialIcons_LICENSE.txt` states CC-BY-4.0), Cupertino Icons
  (`cupertino_icons` 2.0.0, MIT, copyright (c) 2016 Vladimir Kharlampidi), Yaru
  Icons from [yaru.dart](https://github.com/ubuntu/yaru.dart) (CC-BY-SA-4.0),
  and Ubuntu/Ubuntu Mono (Ubuntu Font Licence 1.0, copyright Canonical Ltd.;
  the font files retain their copyright metadata).
  Yaru 11.0.0's theme/widgets are MPL-2.0; its GPLv3 scripts are development tools.
  Font subsetting during a Flutter build can modify icon-font binaries.
- The nine screenshots under `inspiration/` entered Git in the 2026-03-09
  snapshots (`dffdabe`, `db41538`), and reappear in `e18a8b0`. No source URL,
  capture-author statement, permission, or PNG attribution metadata was found.
  Toolkit captures show version 2.31.0.0; the
  [upstream project has a GPLv3 license](https://github.com/BartoszCichecki/LenovoLegionToolkit/blob/63c173024495bae37283e247f11953a09f79ba11/LICENSE),
  but the repository does not identify who made these captures or record
  permission to redistribute them. Legion Zone is Lenovo software; permission
  to redistribute its screenshots is also unverified.
  These references are not app assets and are excluded from `git archive` source
  releases by `.gitattributes`. They remain in the development repository.
- Development guidance under `.agents/skills/` is separate from runtime assets.
  Existing notices, including `.agents/skills/frontend-design/LICENSE.txt`,
  remain applicable.

## Release notices

`flutter build linux --release` keeps Flutter's generated
`data/flutter_assets/NOTICES.Z` and installs this notice, the project license,
vendor attribution, and nested font/native licenses under
`share/licenses/legion_frontend/`. Full notice text is copied from the resolved
dependencies and SDK, without replacing their original notices.

Flutter collects package-root `LICENSE`/`NOTICES` files, including development
dependencies, and engine notices. `tool/bundle_notices.dart` records which packages
the app depends on at runtime, along with the
font manifest, native libraries, and notice component names in `inventory.json`.
It adds the nested notices Flutter misses: Yaru's `assets/LICENSE.CCBYSA` and
`assets/fonts/LICENCE.txt`, handy_window's libhandy `COPYING`/`AUTHORS` and settings
`LICENCE`, and the SDK's `MaterialIcons_LICENSE.txt`.

The inspected Linux bundle includes:

| Native library | Source and notice |
| --- | --- |
| `libflutter_linux_gtk.so`, `data/icudtl.dat` | Flutter engine, ICU and embedded dependencies; generated `NOTICES.Z` |
| `libapp.so` | Compiled application and Dart dependencies; project GPL and `NOTICES.Z` |
| `libhandy_flutter.so` | libhandy 1.5.91 subtree in handy_window 0.4.2; LGPL-2.1-or-later (`linux/libhandy/src/meson.build`, `COPYING`) |
| `libhandy_window_plugin.so` | handy_window 0.4.2 MPL-2.0; copied settings code BSD-3-Clause |
| `libgtk_plugin.so`, `libyaru_window_linux_plugin.so` | gtk 2.2.0 and yaru_window_linux 0.2.2; MPL-2.0 in `NOTICES.Z` |
| `libscreen_retriever_linux_plugin.so`, `libwindow_manager_plugin.so` | screen_retriever_linux 0.2.2 and window_manager 0.5.2; MIT in `NOTICES.Z` |
| `libdartjni.so` | jni 1.1.1 native build hook; BSD-3-Clause in `NOTICES.Z` |

GTK, GLib, libc, the JVM (`libdartjni.so` needs `libjvm.so`) and other host
libraries are dynamically linked, not copied by this bundle. A downstream
AppImage/Flatpak/package that adds libraries
must retain their notices too. The current Settings → About section provides
project/issue links and diagnostics, not a license viewer.

Check a built bundle without changing it:

```sh
dart tool/bundle_notices.dart --check build/linux/x64/release/bundle
gzip -dc build/linux/x64/release/bundle/data/flutter_assets/NOTICES.Z | less
```

Keep both notice locations when packaging. Use `tool/package_release.sh` to
build the bundle and its source companion, including the resolved libhandy
subtree and local dependency edits. Publish both together; see the
[release instructions](README.md#running) for archive contents and rebuild
instructions. Flutter SDK source is identified by SDK-reported versions and
revisions and must be obtained separately, along with source for any host
libraries a downstream package adds. Distributor SDKs can report placeholder
framework revisions; see the release instructions for this limitation.

### Nix Flutter SDK source provenance

The release source manifest does not copy the Flutter SDK. When the SDK is
installed from Nix and its derivations are available, the manifest records the
Flutter source fetch URL and ref, the recursive Nix SHA-256 content hash, the
relevant derivation store names, and identifiers plus SHA-256 hashes for the
SDK patch files. Store names are identifiers only; local derivation paths and
the unfiltered build environment are not published. The Nix hash identifies
the fetched archive bytes and does not claim that a tag is a Git commit. A
non-Nix SDK or collected derivations is reported as unavailable.
