# Privileged Hardware Control Helper

This C++ subproject builds `legion_control_helper`, the privileged helper that
executes allow-listed hardware-control commands and samples package power for
the Flutter desktop app.

## Modules

- **Peer and executable trust:** `control_peer.*`, `trusted_executable.*`,
  `executable_snapshot.*` verify the caller and helper binary before accepting
  commands.
- **Allow-list and command execution:** `control_commands.*`,
  `managed_command.*`, `control_dispatch.*`, `control_protocol.h` validate and
  run allow-listed hardware actions.
- **Session and lifetime:** `helper_bootstrap.cc`, `helper_cli.*`,
  `control_session.*`, `helper_lifetime.*`, `helper_cleanup.cc` manage helper
  startup, the control socket, and process cleanup.
- **Power sampling:** `package_power_sampler.*` reads RAPL/power-meter values
  for the dashboard.
- **Tests and probes:** `test/` holds VM and distro qualification checks;
  `test_support/` and `prototype/` hold hardware-free test doubles and probes.

## Build and test

- **Desktop bundle:** [linux/CMakeLists.txt](../linux/CMakeLists.txt) includes
  this directory automatically and bundles `legion_control_helper` under
  `libexec/`.
- **Standalone build and unit tests:**

```bash
cmake -S control -B build/control -DBUILD_CONTROL_HELPER=ON
cmake --build build/control
ctest --test-dir build/control --output-on-failure
```

For design details, trust boundaries, and VM qualification, see
[the control helper architecture](../docs/architecture/control-helper.md) and
[control helper tests](../docs/architecture/control-helper-tests.md).
