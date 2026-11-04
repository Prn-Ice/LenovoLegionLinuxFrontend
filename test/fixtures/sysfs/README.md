# Hardware file samples

`alternate-layout.json` contains invented values used to test alternate device
paths without a laptop.

`82y4-m1cn48ww-readonly.json` contains readings from the project owner's Legion
Slim 7 16APH8 (`82Y4`, BIOS `M1CN48WW`, kernel `7.3.1`), captured on
2026-11-04 at 12:14 UTC with `LegionSysfsService.readHardwareProbes`. The app was
reading the `low-power` profile while the laptop was on battery. The AC adapter's
`type` file was read separately to reproduce its discovery.

We kept the model fields, selected power settings, fan readings and provider
name, and battery/adapter state to test this laptop's file layout. Each JSON key
is a path relative to a test directory; its value is the file's trimmed text.
These are readings at that time. This capture did not change any settings or
test writing them.
