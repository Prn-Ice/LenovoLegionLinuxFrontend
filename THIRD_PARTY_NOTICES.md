# Third-party notices

The application is licensed under `GPL-2.0-or-later`; see [README.md](README.md#license)
and [LICENSE](LICENSE). Third-party materials retain their own notices and terms.

## OpenRGB Spectrum ports

Primary source: [OpenRGB](https://github.com/CalcProgrammer1/OpenRGB), verified
2026-11-04 at commit `fc3aa07947e82da060a429e0b4b10886c7e0d697`.
This pins the sources inspected for attribution; the original port's exact
upstream revision was not recorded and has not been established.

| Local file | Upstream source at the verified commit |
| --- | --- |
| `lib/features/lighting/services/spectrum_led_map.dart` | [`Controllers/LenovoControllers/LenovoDevices.h`](https://github.com/CalcProgrammer1/OpenRGB/blob/fc3aa07947e82da060a429e0b4b10886c7e0d697/Controllers/LenovoControllers/LenovoDevices.h), `legion7_gen7and8_ansi_leds` and `legion7_gen7and8_neon_leds` |
| `lib/features/lighting/services/spectrum_protocol.dart` | [`LenovoUSBController_Gen7_8.cpp`](https://github.com/CalcProgrammer1/OpenRGB/blob/fc3aa07947e82da060a429e0b4b10886c7e0d697/Controllers/LenovoControllers/LenovoUSBController_Gen7_8/LenovoUSBController_Gen7_8.cpp) and [its header](https://github.com/CalcProgrammer1/OpenRGB/blob/fc3aa07947e82da060a429e0b4b10886c7e0d697/Controllers/LenovoControllers/LenovoUSBController_Gen7_8/LenovoUSBController_Gen7_8.h) |

All three upstream files declare `GPL-2.0-or-later`. The `LenovoDevices.h`
header credits Cooper Hall (geobot19), 17 Apr 2022. OpenRGB's
[LICENSE](https://github.com/CalcProgrammer1/OpenRGB/blob/fc3aa07947e82da060a429e0b4b10886c7e0d697/LICENSE)
contains the GNU GPL version 2 text; the file-level declarations grant the
option of later versions.

These are modified Dart ports. Project history
records the Gen 7/8 encoder port (`ac37a83`) and the LED-table port (`df37f3a`)
on 2026-06-22. The map converts upstream LED entries into name/value pairs.
The encoder extracts packet construction from the C++ HID driver; local changes
include power limiting, white balance, and protocol updates through 2026-08-29
(`21ceffa`). Attribution notices were added on 2026-11-04 without changing behavior.

## Assets and fonts

- `assets/gpu_vendors/{amd,intel,nvidia}.svg`: the
  [asset README](assets/gpu_vendors/README.md) records retrieval from Simple Icons
  on 2026-08-30, its CC0 1.0 project license, and separate brand/trademark caveats.
- Fonts and icons supplied by dependencies retain their own licenses.
  `cupertino_icons` 2.0.0 is MIT, copyright (c) 2016 Vladimir Kharlampidi.
  `yaru` 11.0.0 uses MPL-2.0 for theme/widgets, CC-BY-SA-4.0 for SVG/icon-font
  assets (`assets/LICENSE.CCBYSA`), and GPLv3 for scripts. Keep these and the
  Material Icons notices when distributing the application.
- `inspiration/legion-zone/` and `inspiration/lenovo-legion-toolkit/` contain
  reference screenshots, not declared application assets. No license or
  attribution notice was found alongside them; their redistribution provenance
  remains unresolved.
- Development guidance under `.agents/skills/` is separate from runtime assets.
  Existing notices, including `.agents/skills/frontend-design/LICENSE.txt`,
  remain applicable.

## Release notices

The exact original OpenRGB port revision, screenshot permissions, individual
vendor-mark metadata, and a complete inventory of dependency/runtime notices
remain unverified. Release packaging must retain applicable third-party notices
and provide corresponding source as required by the licenses.
