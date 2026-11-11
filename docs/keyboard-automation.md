# Keyboard profiles by power mode

Save named profiles in **Lighting**, then assign them to Quiet, Balanced,
Performance, or Custom in **Automation**. Each mode starts at **Leave unchanged**.
The app applies assignments when it opens and when its observed power mode
changes. Selecting a profile for the current mode also applies it immediately.

Keep the app open for automatic switching. The existing dashboard poll observes
changes from Fn+Q, the CLI, desktop power settings, and this app; the keyboard
may change after a short delay. Closing the app stops software lighting
animations and automatic switching. Static colors and firmware effects remain
on the keyboard.

Profiles use the existing native Spectrum or OpenRGB backend. Software region
animations require native Spectrum support. The app reports missing profiles,
incompatible keyboards, and failed writes instead of treating them as
successful applications. Use **Apply current profile** to retry after fixing a
problem in Lighting. A manual lighting edit remains in place until the next
assigned mode change or explicit profile application.

## Previous automation settings

We removed the old fan-preset, conservation, rapid-charging, and shell-command
rules. The app ignores their old enabled flags and reads only `keyboardProfiles`.
The next saved assignment replaces the old file with version 2. The app stores
assignments in
`$XDG_CONFIG_HOME/legion_frontend/automation_rules.json`, defaulting to
`~/.config/legion_frontend/automation_rules.json`. Named profile contents remain
in the existing `rgb_lighting` Hive box.

Rapid charging is a normal setting in **Power**, using the existing battery
hardware readback. It can be configured while unplugged but only charges with
external power. The Dashboard shortcut remains available. Fan-preset switching
can be handled by the upstream `legiond` service.
