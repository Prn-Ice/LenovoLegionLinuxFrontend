# Recording a dark-screen sleep problem

The user reported a dark screen with keyboard and power-button lights remaining
on around hibernation. Fan activity and normal shutdown behavior are unknown.
We are investigating this in `lllf-p4q`; intentional sleep tests are paused.
We cancelled the pending iGPU-only request, leaving Hybrid unchanged.

## Leave the recorder running

From a desktop terminal, as your normal user:

```bash
python3 ~/legion-record
```

Leave the terminal open and use the laptop normally. The script prints where it
is saving logs and confirms when journal events arrive. It requests no sleep,
reboot, graphics change, root access, or power-setting change. Ctrl+C stops it.
Closing the terminal or rebooting also ends recording; it is not an installed
background service. The convenience link points to
`tool/record_sleep_events.py` in this checkout.

Logs are private timestamped folders under
`${XDG_STATE_HOME:-$HOME/.local/state}/legion-sleep-recorder/`. They contain up to
four 8 MiB JSON-lines files per run; older events are replaced when the files
fill. Each saved event and directory update is flushed to disk. Existing runs
are retained, so repeated runs can use more disk space. The files may contain
process names, device identifiers, and kernel messages; review before sharing.

The data comes from the system journal. We include kernel messages, systemd
sleep services, login management, the graphics boot helper, KWin display events,
and PowerDevil's sleep/error messages. Routine PowerDevil display-bus polling is
filtered out so it does not overwrite the useful history. The recorder copies the
last 30 minutes on startup, followed by new events. Reading these logs works with
the current user's journal access; if permissions change, incomplete access may
omit some sources. Seeing one event is not proof that every source is available.

If the problem occurs naturally, note roughly when, which lights remain on,
whether a single power-button press changes anything, and whether you see a
boot logo afterward. Do not run another forced-off experiment just to collect
these observations. Tell the agent what happened after you can use the desktop
again; it can read the files directly.

## What these logs can and cannot establish

User programs freeze during system sleep and hibernation. This recorder freezes
too. It preserves events it receives before and after the freeze, not the exact
physical power-off boundary. A forced power cut may still lose messages that
had not reached the journal or recorder. Restoring a hibernation image also
restores old process state, so abrupt-cut logs may contain an incomplete tail
or repeated events. A flushed file does not eliminate storage/firmware risks.

The host already installs a separate hibernation hook that writes snapshots
under `/var/log/legion-hibernate-diagnostics/`. This recorder does not arm,
modify, or replace it, and does not enable kernel PM debug flags. The snapshots
and journal exports complement one another but neither proves that the chassis
actually lost power. Kernel-side persistent tracing or external power evidence
would need a separate reviewed plan if ordinary logs cannot locate the fault.

The two existing incident logs show image-return evidence and, in the later
cycle, another PowerDevil suspend request about 30 seconds after thaw. KWin also
reported missing DRM devices and permission errors during output restoration.
These facts do not establish whether the user's original problem was final
power-off, display recovery, a button-triggered second sleep, or another cause.

## Verification

`python3 tool/test_record_sleep_events.py` tests the journal command, filtering,
private file permissions, JSON persistence, size bounds, and rotation without
hardware or system services. A real journal read confirms the current user can
read kernel events. No sleep or power-off experiment is part of these checks.
