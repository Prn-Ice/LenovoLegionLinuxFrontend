# Third-party notices

The application is licensed under `GPL-2.0-or-later`; see [README.md](README.md#license)
and [LICENSE](LICENSE). Third-party materials retain their own notices and terms.
This is a focused provenance record, not a complete dependency or asset clearance.
`LICENSE` is a verbatim copy of the Free Software Foundation's
[GPL version 2 text](https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt),
verified byte-for-byte on 2026-11-04.

## OpenRGB Spectrum ports

Primary source: [OpenRGB](https://github.com/CalcProgrammer1/OpenRGB), verified
2026-11-04 at commit `fc3aa07947e82da060a429e0b4b10886c7e0d697`.
This pins the sources inspected for attribution; the original port's exact
upstream revision was not recorded and has not been established.

| Local file | Upstream source at the verified commit |
| --- | --- |
| `lib/features/lighting/services/spectrum_led_map.dart` | [`Controllers/LenovoControllers/LenovoDevices.h`](https://github.com/CalcProgrammer1/OpenRGB/blob/fc3aa07947e82da060a429e0b4b10886c7e0d697/Controllers/LenovoControllers/LenovoDevices.h), `legion7_gen7and8_ansi_leds` and `legion7_gen7and8_neon_leds` |
| `lib/features/lighting/services/spectrum_protocol.dart` | [`LenovoUSBController_Gen7_8.cpp`](https://github.com/CalcProgrammer1/OpenRGB/blob/fc3aa07947e82da060a429e0b4b10886c7e0d697/Controllers/LenovoControllers/LenovoUSBController_Gen7_8/LenovoUSBController_Gen7_8.cpp) and [its header](https://github.com/CalcProgrammer1/OpenRGB/blob/fc3aa07947e82da060a429e0b4b10886c7e0d697/Controllers/LenovoControllers/LenovoUSBController_Gen7_8/LenovoUSBController_Gen7_8.h) |

All three upstream files say `This file is part of the OpenRGB project` and
`SPDX-License-Identifier: GPL-2.0-or-later`. `LenovoDevices.h` credits
`Cooper Hall (geobot19)` with the date `17 Apr 2022`; this is a file-header
credit, not a claim that this person solely authored the Gen 7/8 tables.
The two protocol-file headers contain no individual author or copyright line.
No additional copyright holder is inferred here. OpenRGB's
[LICENSE](https://github.com/CalcProgrammer1/OpenRGB/blob/fc3aa07947e82da060a429e0b4b10886c7e0d697/LICENSE)
contains the GNU GPL version 2 text; the file-level declarations grant the
option of later versions.

These are modified Dart ports, not unmodified OpenRGB files. Project history
records the Gen 7/8 encoder port (`ac37a83`) and the LED-table port (`df37f3a`)
on 2026-06-22. The map converts upstream LED entries into name/value pairs.
The encoder extracts packet construction from the C++ HID driver; local changes
include power limiting, white balance, and protocol updates through 2026-08-29
(`21ceffa`). Attribution notices were added on 2026-11-04 without changing behavior.

## Assets and fonts

- `assets/gpu_vendors/{amd,intel,nvidia}.svg`: the existing
  [asset README](assets/gpu_vendors/README.md) records retrieval from Simple Icons
  on 2026-08-30, its CC0 1.0 project license, and separate brand/trademark caveats.
  This does not establish that every vendor mark is free of separate restrictions;
  individual icon metadata and vendor permissions have not been reverified here.
- No standalone font files are tracked in this repository, and `pubspec.yaml`
  declares no custom font family. It enables Material Icons and depends on
  `cupertino_icons` and `yaru`; dependency-supplied fonts/icons are not relicensed
  by the application's GPL declaration. The locally resolved `cupertino_icons`
  2.0.0 `LICENSE` is MIT, copyright (c) 2016 Vladimir Kharlampidi. The resolved
  `yaru` 11.0.0 README distinguishes MPL-2.0 theme/widgets from CC-BY-SA-4.0
  SVG/icon-font assets (`assets/LICENSE.CCBYSA`) and GPLv3 scripts. Retain those
  package notices in distributions. Material Icons and other transitive font
  or asset notices still need a release-bundle inventory.
- `inspiration/legion-zone/` and `inspiration/lenovo-legion-toolkit/` contain
  reference screenshots, not declared application assets. No license or
  attribution notice was found alongside them; their redistribution provenance
  remains unresolved. The application license does not claim rights to them.
- Development guidance under `.agents/skills/` is separate from runtime assets.
  Existing notices, including `.agents/skills/frontend-design/LICENSE.txt`,
  remain applicable. This review does not establish provenance for all vendored
  guidance or all other repository content.

## Remaining verification

The exact original OpenRGB port revision, screenshot permissions, individual
vendor-mark metadata, and a complete inventory of dependency/runtime notices
remain unverified. Release packaging must retain applicable third-party notices
and provide corresponding source as required by the licenses; this document
does not assert that a built distribution has already been audited.
