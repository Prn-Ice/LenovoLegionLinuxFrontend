# Temporary local CI

`CI_RUNNER=mac-legion-linux-x64` routes compatible jobs to this Mac. These
include path selection, Flutter tests, AppImage/Debian builds, commit checks
and OSV scans. Fork PRs use hosted runners in these workflows.

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

`ci-legion` and `ci-legion-2` each run one job. Each machine runs Ubuntu 24.04
x64 through Rosetta with two CPUs, a 4 GiB memory limit and a 25 GiB disk limit.
Each has its own Docker daemon and caches, no Mac file mounts or SSH agent
forwarding, and no access to the other machines.

Flutter tests reuse the installed SDK and `~/.pub-cache`. Tests on a cold runner
and package builds use the same checksum-verified SDK archive under
`~/.cache/legion-ci`. AppImage runtime inputs stay there too. The two package
formats share Pub downloads in the local Docker volume `legion-package-pub`.
They also share a builder image tagged with its Dockerfile checksum. BuildKit
retains apt indexes and packages even if the install step fails. To refresh
system dependencies without changing the recipe, run
`bash tool/packaging/package_builder_image.sh` without `RUNNER_ENVIRONMENT`, after
invalidating the Docker build cache if a fresh install is required.
Package artifacts still go to GitHub for the hosted acceptance jobs.
Docker uses its supported `cgroupfs` driver in `/etc/docker/daemon.json`, because
systemd's container-scope process checks fail under Rosetta.
Install `fuse-overlayfs` and set `features.containerd-snapshotter=false` and
`storage-driver=fuse-overlayfs` in Docker's config. The default snapshotter
could not mount build layers, and with `overlay2`, `dpkg` could not install new
directories. The runners keep the FUSE store in `/var/lib/docker-legion-fuse`.
The local Flutter job runs one test worker to fit its 4 GiB memory limit.
After changing Docker configuration, stop and start the idle OrbStack machine
so both Docker and the runner restart cleanly.

Keep the Mac connected to power and online. The shared user LaunchAgent
`ng.prnice.github-runners-awake` runs `caffeinate -s` to prevent idle sleep on
power. Closing the lid can still suspend the Mac.

```sh
for machine in ci-legion ci-legion-2; do
  orb start "$machine"
  orb -m "$machine" -w /home/runner/actions-runner sudo ./svc.sh status
done
```

To pause, restore hosted routing, let active jobs finish, then run
`orb stop ci-legion` and `orb stop ci-legion-2`. Queued jobs retain their labels;
cancel and rerun them after changing the variable. After restarting the Mac,
start OrbStack and both machines.

To remove the setup, restore hosted routing, remove both runners under GitHub
**Settings → Actions → Runners**, then delete both machines and their caches in OrbStack.

After all three projects return to hosted CI, stop the shared awake service:
`launchctl bootout gui/$(id -u)/ng.prnice.github-runners-awake`. Then remove
`~/Library/LaunchAgents/ng.prnice.github-runners-awake.plist`.
