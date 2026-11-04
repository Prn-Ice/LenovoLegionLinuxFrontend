---
name: code-patterns
description: Project-owned guidance for readable Dart, repeatable Riverbloc patterns, hardware boundaries, meaningful tests, and stable dependency upgrades. Read before implementation, review, or test work.
---

# Code the next maintainer can follow

Read `AGENTS.md` and the relevant existing feature before changing code. These
patterns adapt [Ester's working agreement](https://github.com/Prn-Ice/ester/blob/6964c5bce2628cc7a6b0f0a5c0af0332926d3ee2/AGENTS.md)
and its project-owned code-patterns skill. They are tool-neutral guidance, not
another agent workflow or a requirement to install external skills.

## Read the reference for the work

Load the relevant guides before implementing or reviewing, not every reference
on every task. They apply to existing code encountered as well as new code.

| Work | Reference |
| --- | --- |
| Bloc/Cubit, provider wiring, listeners, async work, concurrency, disposal | [Riverbloc](references/riverbloc.md) |
| Concrete provider, callback, and test shapes | [Riverbloc examples](references/riverbloc-patterns.md) |
| Version-sensitive API claims or stale upstream examples | [Resolved API source map](references/riverbloc-api.md) |
| Tests, races, hardware boundaries, responsive evidence | [Testing](references/testing.md) |
| Flutter pages, Yaru components, dialogs, theme, accessibility | [Flutter UI](references/flutter-ui.md), then `docs/page-template.md` and `docs/error-and-feedback-standard.md` |
| SDK/package upgrades | `docs/dependencies.md` and the upgrade section below |

These references adapt
[Ester's focused code-patterns guides](https://github.com/Prn-Ice/ester/tree/6964c5bce2628cc7a6b0f0a5c0af0332926d3ee2/.agents/skills/code-patterns/references).
They deliberately exclude its estate model, Supabase/RLS, Jaspr,
AutoRoute, monorepo, design system, and Git policy. This project's architecture,
UI standards, and completion rules remain authoritative.

## Keep the behavior visible

- Read construction, callers, failure handling, and cleanup together. State the
  behavior being preserved before choosing a pattern.
- Prefer product-language names and straightforward statements. Extract helpers
  for meaningful responsibilities or repeated contracts, not file-size targets.
- Always prefer enums to strings for named choices such as commands, settings,
  modes, and states. Reuse an existing enum when one fits. Convert to protocol
  strings in the service that sends them, so callers get autocomplete and
  compiler checks instead of having to copy the right spelling.
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

## Say what things are

Use ordinary language in comments, docs, UI copy, and handoffs. Say what the
thing is, where it came from, and what we use it for when those facts matter.

For example: "These power settings were recorded from one laptop and chosen as
the app's defaults" explains more than "display reference values for an exact
product and BIOS match."

State choices directly. Do not make the reader decode abstract labels or a list
of things something is not. Include a limitation when it affects how someone
should use the thing, beside the relevant instruction.

Follow the **Direct writing** rules in `AGENTS.md` for responses as well as
project text. State the main point and stop when it is complete. Remove trailing
“not a…”, “does not mean…”, and “no … needed” explanations unless they change
the reader's action or understanding. State each necessary limitation once.

Write “Other models and BIOS versions have not been tested.” A comparison with
upstream driver support adds nothing to that statement. Link to the public
backlog directly; omit explanations about needing access to internal tooling.

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
