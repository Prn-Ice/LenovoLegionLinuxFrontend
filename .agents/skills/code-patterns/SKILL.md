---
name: code-patterns
description: Project-owned guidance for readable Dart, repeatable Riverbloc patterns, hardware boundaries, meaningful tests, and stable dependency upgrades. Read before implementation, review, or test work.
---

# Code the next maintainer can follow

Read `AGENTS.md` and the relevant existing feature before changing code. These
patterns adapt [Ester's working agreement](https://github.com/Prn-Ice/ester/blob/1d73e16481ce73aa16e3764053530f0a6980d7fe/AGENTS.md)
and its project-owned code-patterns skill. They are tool-neutral guidance, not
another agent workflow or a requirement to install external skills.

## Keep the behavior visible

- Read construction, callers, failure handling, and cleanup together. State the
  behavior being preserved before choosing a pattern.
- Prefer product-language names and straightforward statements. Extract helpers
  for meaningful responsibilities or repeated contracts, not file-size targets.
- Keep cohesive behavior together. Do not introduce wrappers, DTO/entity pairs,
  providers per field, or a second dependency-injection tree without a real need.
- Use ordinary co-located Riverbloc providers. Bloc/Cubit owns feature behavior;
  Riverpod supplies dependencies and disposal. Do not rewrite a sound Bloc just
  to reduce boilerplate or migrate it to a Notifier during maintenance.
- Prefer native framework patterns. Explain the problem, simpler alternative,
  and trade-off before introducing unfamiliar coordination or custom abstractions.
- Correct safe, relevant problems encountered in existing code and search for
  related occurrences. Ask before behavior changes or broader migrations; link
  exact locations and a proposed correction in Beads when outside this task.

## Respect the hardware boundary

Repositories use services for hardware access. Read-only sysfs and telemetry
remain unprivileged. Writes go through `LegionControlClient` and the typed
`io.github.prnice.LegionControl1` D-Bus API. Preserve Polkit authorization and the
C++ allow-list; never add a generic root command or privilege-elevation fallback.

For page work, follow `docs/page-template.md` and
`docs/error-and-feedback-standard.md`. Reuse existing shared components and
theme values rather than creating a second visual system. Keep presentation
components focused on values and callbacks; local presentation state may stay
local. This skill does not authorize a visual redesign.

## Prove the changed promise

- Test real transitions, failures/retry, validation, resource ownership, and races
  where relevant. No coverage quotas or obligatory test for every trivial getter.
- Use repository/service fakes for hardware-free tests. Do not rely on the
  developer's actual device, system bus, or privileged service for unit tests.
- Test provider initialization and disposal when upgrading Riverpod/Riverbloc;
  manually constructed Bloc tests alone do not prove dependency wiring.
- Use controlled completion for async tests, not arbitrary sleeps. Own and close
  clients, subscriptions, timers, and Blocs once.
- Tests, generation, builds, visual review, and real hardware checks prove
  different things. Report missing evidence explicitly.

## Upgrade deliberately

Use Context7 and primary release notes for version-sensitive APIs; check resolved
source when examples disagree. Disclose failed lookups rather than inventing APIs.
Probe conflicts in a disposable copy, then update the manifest and lock together.
Do not hand-edit generated files, weaken tests, or use incompatible overrides.

Run real Hive generation, static analysis, the full Flutter suite, and a Linux
release build. Check equality and Riverbloc lifetime contracts, not only resolver
success. Record version constraints and their removal conditions in
`docs/dependencies.md`; keep live decisions and verification evidence in Beads.

Preserve unrelated staged, unstaged, and untracked work. A shared SDK update
affects other projects: confirm its scope before changing it. Shell entry must
not start services, alter hardware, or install unrelated tools. Follow this
repository's completion policy, not a copied sibling's Git policy.
