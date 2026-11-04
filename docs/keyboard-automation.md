# Keyboard profiles by power mode

Save named profiles in **Lighting**, then assign them to Quiet, Balanced,
Performance, or Custom in **Automation**. Each mode starts at **Leave unchanged**.
The assignments are applied when the app opens and when its observed power mode
changes. Selecting a profile for the current mode also applies it immediately.

Keep the app open for automatic switching. The existing dashboard poll observes
changes from Fn+Q, the CLI, desktop power settings, and this app; there can be a
short delay before the keyboard changes. Closing the app stops software lighting
animations and automatic switching. Static colors and firmware effects are left
on the keyboard.

Profiles use the existing native Spectrum or OpenRGB backend. Software region
animations require native Spectrum support. Missing profiles, incompatible
keyboards, and failed writes are reported rather than treated as successful
applications. Use **Apply current profile** to retry after fixing a problem in
Lighting. A manual lighting edit remains in place until the next assigned mode
change or explicit profile application.

## Previous automation settings

The old fan-preset, conservation, rapid-charging, and shell-command rules have
been removed. Existing enabled flags cannot execute. The configuration reader
only reads `keyboardProfiles`; the next assignment save replaces the old file
with version 2. Assignments are stored in
`$XDG_CONFIG_HOME/legion_frontend/automation_rules.json`, defaulting to
`~/.config/legion_frontend/automation_rules.json`. Named profile contents remain
in the existing `rgb_lighting` Hive box.

Rapid charging is a normal setting in **Power**, using the existing battery
hardware readback. It can be configured while unplugged but only charges with
external power. The Dashboard shortcut remains available. Fan-preset switching
can be handled by the upstream `legiond` service.
