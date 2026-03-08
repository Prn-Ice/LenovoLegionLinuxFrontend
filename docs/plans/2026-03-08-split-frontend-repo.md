# Split Flutter Frontend into Separate Repository

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract `frontend/legion_frontend/` from the LenovoLegionLinux monorepo into its own standalone GitHub repository, preserving git history.

**Architecture:** Use `git subtree split` to extract the 68 frontend commits into a clean branch, push that branch to a new GitHub repo as `main`, update project metadata (README, app ID, pubspec description), add a GitHub Actions CI workflow, and leave a reference pointer in the monorepo. The frontend-to-backend coupling is entirely through the system-installed `legion_cli` binary — no source-level dependency on the Python code — so the split requires no code changes.

**Tech Stack:** Git, GitHub CLI (`gh`), Flutter, GitHub Actions

**NOTE:** All flutter commands must be run from inside `frontend/legion_frontend/`. Python is irrelevant to this plan.

**Prerequisites (manual — do before starting):**
1. Create a new empty GitHub repository named `LenovoLegionLinuxFrontend` (no README, no .gitignore, no license) at `https://github.com/Prn-Ice/LenovoLegionLinuxFrontend`
2. Confirm the remote URL: `git@github.com:Prn-Ice/LenovoLegionLinuxFrontend.git`

**Rollback plan:**
- The monorepo is NOT modified until Task 4. All changes up to that point are in the new repo only.
- If the new repo is unusable, delete it on GitHub and discard the local `flutter-extracted` branch: `git branch -D flutter-extracted`
- The monorepo `frontend/legion_frontend/` directory is untouched and remains fully functional throughout.

---

### Task 1: Extract git history into a standalone local repo

**Goal:** Create a local copy of the new repo with the full 68-commit history rewritten so `frontend/legion_frontend/` is the root.

**Files:**
- No source files changed — git operations only

**Step 1: Split the subtree into a local branch**

Run from `/home/prnice/Projects/personal/LenovoLegionLinux`:

```bash
git subtree split --prefix=frontend/legion_frontend --branch flutter-extracted
```

Expected output: a SHA printed (the tip of the extracted branch). This may take 30–60 seconds.

**Step 2: Create a new local repo from the extracted branch**

```bash
cd /tmp
git clone /home/prnice/Projects/personal/LenovoLegionLinux --branch flutter-extracted --single-branch LenovoLegionLinuxFrontend
cd LenovoLegionLinuxFrontend
git log --oneline | head -10
```

Expected: git log shows Flutter-only commits (e.g. `feat(dgpu): add DgpuPage...`), with no Python commits.

**Step 3: Verify the repo root looks correct**

```bash
ls
```

Expected: `lib/`, `test/`, `pubspec.yaml`, `linux/`, `docs/`, `analysis_options.yaml`, `README.md` — not `python/`, `drivers/`, etc.

**Step 4: Rename branch to main**

```bash
git branch -m flutter-extracted main
```

**Step 5: Run tests to confirm the extraction is clean**

```bash
cd /tmp/LenovoLegionLinuxFrontend
flutter pub get
flutter test --reporter=compact 2>&1 | tail -5
```

Expected: all 174 tests pass.

---

### Task 2: Update project metadata

**Goal:** Replace placeholder metadata with accurate project identity.

**Files:**
- Modify: `README.md`
- Modify: `pubspec.yaml`
- Modify: `linux/CMakeLists.txt`

**Step 1: Replace README.md**

Replace the entire file with:

```markdown
# Legion Linux Frontend

A Flutter-based desktop frontend for [LenovoLegionLinux](https://github.com/johnfanv2/LenovoLegionLinux) — the open-source Linux kernel module and tooling for Lenovo Legion laptops.

## Features

- Fan curve editor
- Power profile / platform profile switching
- Battery conservation and rapid charging
- Fn-lock, touchpad, camera toggles
- Boot logo customization
- Discrete GPU monitoring and deactivation
- Automation (run external programs on profile change)
- Display lighting (LampArray)
- Real-time dashboard

## Requirements

- `legion_linux` kernel module installed (provides sysfs interface)
- `legion_cli` installed and in PATH (provides privileged write access via polkit)
- NVIDIA driver (optional, for dGPU features)

## Running

```bash
flutter run -d linux
```

Or build a release binary:

```bash
flutter build linux --release
```

## Development

```bash
flutter test
flutter analyze
```

## Architecture

The frontend communicates with the backend exclusively through the system-installed `legion_cli` binary. No direct sysfs writes from Dart — all privileged operations go through `pkexec legion_cli <subcommand>`. Read operations use direct sysfs file reads via `dart:io`.

See `docs/architecture/` for detailed documentation.
```

**Step 2: Update pubspec.yaml description**

In `pubspec.yaml`, change:

```yaml
description: "A new Flutter project."
```

to:

```yaml
description: "Flutter desktop frontend for LenovoLegionLinux — laptop control on Linux."
```

**Step 3: Update APPLICATION_ID in CMakeLists.txt**

In `linux/CMakeLists.txt`, change:

```cmake
set(APPLICATION_ID "com.example.legion_frontend")
```

to:

```cmake
set(APPLICATION_ID "io.github.prnice.legion_linux_frontend")
```

**Step 4: Verify analyze still passes**

```bash
flutter analyze
```

Expected: 0 errors, 0 warnings.

**Step 5: Commit**

```bash
git add README.md pubspec.yaml linux/CMakeLists.txt
git commit -m "chore: update project metadata for standalone repository"
```

---

### Task 3: Add GitHub Actions CI workflow

**Goal:** Automated test + analyze on every push and pull request.

**Files:**
- Create: `.github/workflows/ci.yml`

**Step 1: Create the workflow directory and file**

```bash
mkdir -p .github/workflows
```

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    name: Flutter Test & Analyze
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install dependencies
        run: flutter pub get

      - name: Analyze
        run: flutter analyze

      - name: Run tests
        run: flutter test --reporter=compact
```

**Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow for test and analyze"
```

---

### Task 4: Push to GitHub and add monorepo pointer

**Goal:** Publish the new repo and leave a breadcrumb in the monorepo.

**Files:**
- Create: `/home/prnice/Projects/personal/LenovoLegionLinux/frontend/FRONTEND_REPO.md` (monorepo pointer)

**Step 1: Add remote and push**

```bash
cd /tmp/LenovoLegionLinuxFrontend
git remote add origin git@github.com:Prn-Ice/LenovoLegionLinuxFrontend.git
git push -u origin main
```

Expected: push succeeds, branch `main` tracking `origin/main`.

**Step 2: Verify CI triggered on GitHub**

```bash
gh run list --repo Prn-Ice/LenovoLegionLinuxFrontend --limit 3
```

Expected: one workflow run in `queued` or `in_progress` state.

**Step 3: Add pointer file in monorepo**

In `/home/prnice/Projects/personal/LenovoLegionLinux`, create `frontend/FRONTEND_REPO.md`:

```markdown
# Flutter Frontend

The Flutter frontend has been extracted to its own repository:

**https://github.com/Prn-Ice/LenovoLegionLinuxFrontend**

The `legion_frontend/` directory here is retained as a reference copy.
To work on the frontend, use the standalone repository above.
```

**Step 4: Commit pointer to monorepo**

```bash
cd /home/prnice/Projects/personal/LenovoLegionLinux
git add frontend/FRONTEND_REPO.md
git commit -m "docs(frontend): add pointer to standalone Flutter frontend repository"
```

---

### Task 5: Final verification

**Goal:** Confirm the new repo is independently usable from a fresh clone.

**Step 1: Clone fresh copy**

```bash
cd /tmp
git clone git@github.com:Prn-Ice/LenovoLegionLinuxFrontend.git verify-frontend
cd verify-frontend
```

**Step 2: Run full verification**

```bash
flutter pub get
flutter analyze 2>&1
flutter test --reporter=compact 2>&1 | tail -5
```

Expected:
- `flutter analyze`: 0 errors, 0 warnings
- `flutter test`: all 174 tests pass

**Step 3: Confirm git log is clean**

```bash
git log --oneline | head -5
git log --oneline | wc -l
```

Expected: log shows Flutter-only commits, ~70 total (68 extracted + 2 metadata commits).

**Step 4: Check CI result on GitHub**

```bash
gh run list --repo Prn-Ice/LenovoLegionLinuxFrontend --limit 3
```

Expected: latest run shows `completed` / `success`.

**Step 5: Clean up temp directories**

```bash
rm -rf /tmp/LenovoLegionLinuxFrontend /tmp/verify-frontend
```

---

## Versioning Approach

The extracted repo starts at `v0.1.0` (pre-release, in active development). Tag after first stable release:

```bash
git tag -a v0.1.0 -m "Initial standalone release"
git push origin v0.1.0
```

Future versions follow `MAJOR.MINOR.PATCH` matching `pubspec.yaml` `version:`.

## Migration Checklist

- [ ] New GitHub repo created (empty, no auto-README)
- [ ] `git subtree split` completed successfully
- [ ] All 174 tests pass in extracted repo
- [ ] README, pubspec description, APPLICATION_ID updated
- [ ] CI workflow added and passing on GitHub
- [ ] Monorepo pointer committed
- [ ] Fresh clone verified (tests pass, analyzer clean)
- [ ] Temp directories cleaned up
