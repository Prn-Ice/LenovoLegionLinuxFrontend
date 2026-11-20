# Hardware file samples

`alternate-layout.json` contains invented values used to test alternate device
paths without a laptop.

`82y4-m1cn48ww-readonly.json` contains readings from the project owner's Legion
Slim 7 16APH8 (`82Y4`, BIOS `M1CN48WW`, kernel `7.3.1`), captured on
2026-11-04 at 12:14 UTC with `LegionSysfsService.readHardwareProbes` in the
`low-power` profile on battery. We read the AC adapter's `type` file separately
to reproduce its discovery.

`82y4-m1cn48ww-kernel734-readonly.json` contains read-only readings from the
same laptop (`82Y4`, BIOS `M1CN48WW`, kernel `7.3.4`,
`lenovo-legion-module-0.1.8-unstable-2026-11-17`, fork merge `baafe12`),
captured on 2026-11-19 in the `low-power` profile on battery. We captured these
values with `LegionSysfsService` readers and direct read-only reads of
`cpu_longterm_powerlimit_defaults` and `cpu_shortterm_powerlimit_defaults`. We
keep this file separate from the 2026-11-04 Kernel `7.3.1` capture so Kernel
`7.3.1` and Kernel `7.3.4` behavior remain unmixed. It preserves the new
`level`-unit speed-only fan table (`pwm1_auto_point1..10_pwm`, `0..4700` RPM
ladders), readable `fan_fullspeed`, `rapidcharge`, and `gpu_ppab_powerlimit`
(`20`), and absent `minifancurve`, `lockfancontroller`, and `fan2_max` files.
This capture changed no settings and tested no writes.

We kept the model fields, selected power settings, fan readings and provider
name, and battery/adapter state to test this laptop's file layout. Each JSON key
is a path relative to a test directory; its value is the file's trimmed text.
These are readings at that time. This capture did not change any settings or
test writing them.
