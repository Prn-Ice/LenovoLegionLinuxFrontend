# Temporary local CI

`CI_RUNNER=mac-legion-linux-x64` routes compatible jobs to this Mac. These
include path selection, Flutter tests, AppImage/Debian builds, commit checks
and OSV scans. Fork PRs use hosted
runners in these workflows.

KVM acceptance jobs stay on GitHub: `control-lifecycle`, `appimage`,
`nix-frontend` and `debian`. OrbStack on this M1 Pro has no nested KVM.
Native syscall tests and Linux desktop integration also stay hosted: pidfd and
sealed-file execution checks fail under Rosetta, and the desktop test runner
fails during cleanup.
The release workflow's tag-check and publishing jobs also remain hosted.
Standard GitHub-hosted runners are free for this public repository.

Remove the variable to restore hosted execution for every job:

```sh
gh variable delete CI_RUNNER --repo Prn-Ice/LenovoLegionLinuxFrontend
```

The repository has one runner in the isolated OrbStack machine `ci-legion`
(Ubuntu 24.04 x64 through Rosetta, two CPUs, a 4 GiB memory limit and a 25 GiB
disk limit). Jobs run sequentially. It has its own Docker daemon, no Mac file
mounts or SSH agent forwarding, and cannot access other local machines.
Docker uses its supported `cgroupfs` driver in `/etc/docker/daemon.json`, because
systemd's container-scope process checks fail under Rosetta.
It also uses the classic `overlay2` image store
(`features.containerd-snapshotter=false` and `storage-driver=overlay2`);
the containerd snapshotter cannot mount build layers in this machine.
After changing Docker configuration, stop and start the idle OrbStack machine
so both Docker and the runner restart cleanly.

Keep the Mac connected to power and online. The shared user LaunchAgent
`ng.prnice.github-runners-awake` runs `caffeinate -s` to prevent idle sleep on
power. Closing the lid can still suspend the Mac.

```sh
orb start ci-legion
orb -m ci-legion -w /home/runner/actions-runner sudo ./svc.sh status
```

To pause, wait for the current job to finish, restore hosted routing, then run
`orb stop ci-legion`. Queued jobs retain their selected labels; cancel and rerun
them after changing the variable. The service starts with its Linux machine.
After restarting the Mac, start OrbStack and this machine.

To remove the setup, restore hosted routing, remove the runner under GitHub
**Settings → Actions → Runners**, then delete `ci-legion` in OrbStack. Deleting
the machine also removes its caches.

After all three projects return to hosted CI, stop the shared awake service:
`launchctl bootout gui/$(id -u)/ng.prnice.github-runners-awake`. Then remove
`~/Library/LaunchAgents/ng.prnice.github-runners-awake.plist`.
