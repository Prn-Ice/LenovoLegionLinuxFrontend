# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Pull requests are required

- **Every change to `main` must go through a PR. Never push directly to `main`.**
- Work on a separate branch. Sign commits, verify their signatures, push the
  branch, and open or update a PR targeting `main`.
- Keep the PR branch up to date with `main`. Required GitHub checks must pass
  before merging; do not bypass or disable branch protection, including as admin.
- If a required check fails or blocks merging, fix it or report the blocker.
  Do not weaken the check to finish the task.
- Do not merge a PR unless the user asks. A session can end with a pushed branch
  and an open PR; report its link and any checks still pending.

## Simple code and repeatable patterns

Read [the project code patterns](.agents/skills/code-patterns/SKILL.md) before
implementation, review, or test work. These adapt Ester's working agreement to
this Linux hardware frontend; Ester's product and deployment rules do not apply.

- Prefer plain names, direct control flow, focused functions, and a visible happy
  path. Optimize for the next reader, not the fewest lines.
- Use Dart for application code and structured tools, Nix for packaging and
  environments, and shell for command orchestration. Do not add Python code.
  Do not introduce another language unless the existing languages cannot meet
  a concrete requirement. Explain the need, alternatives, and maintenance cost,
  and obtain approval before adding one. Keep existing platform-required code
  and upstream tool internals; this rule does not require rewriting dependencies.
- Always prefer enums to strings for named choices such as commands, settings,
  modes, and states. Convert to protocol strings at the service boundary.
- Add an abstraction only when it clarifies a responsibility, isolates an external
  boundary, or centralizes a repeated contract. No empty layers or forwarding
  providers for their own sake.
- Improve relevant code encountered in the task. Discuss behavior changes and
  wider migrations first; record exact paths and proposed fixes in linked Beads
  work rather than expanding scope silently.
- Keep Riverbloc with Bloc/Cubit for feature behavior; Riverpod supplies
  dependencies and lifetime. Reuse existing feature and shared-widget patterns.
- Prefer the latest mutually compatible stable dependencies. Do not force
  prereleases or incompatible overrides to erase constraints. Document retained
  versions in [docs/dependencies.md](docs/dependencies.md).
- Say what things are and what we use them for, in ordinary language. For data,
  say where it came from and why we chose it. Apply this to comments, docs, UI
  copy, and handoffs. See the writing examples in the project code patterns.
- Separate what changed, what was tested, and what remains unverified.

## Standard workflows and simple solutions

- Use supported platform and upstream workflows for installation, launch, and
  runtime compatibility. Keep the user's steps as simple as the standard flow.
- Reject custom, overcomplicated workarounds. When our design conflicts with a
  standard workflow, fix the integration or simplify the design. Do not make
  users adopt a project-specific launcher, compatibility layer, or alternate
  deployment path to hide that conflict.
- Start with the documented workflow and reproduce its failure in the intended
  environment. Check supported configuration and existing platform tools before
  proposing new infrastructure. Explain the root cause and the smallest fix.
- If a custom mechanism is unavoidable, explain why simpler supported options
  fail, its user impact, and its maintenance cost. Obtain explicit user agreement
  to that concrete exception before implementing it. A general request to fix a
  problem or proceed does not approve added architectural complexity.
- Acceptance checks must run the standard user command and exercise the promised
  behavior. Passing a custom test launcher alone does not establish platform
  compatibility. Report the standard flow as unsupported until it passes.
- Preserve authorization and trust checks while fixing integration. If a safe,
  simple solution is unresolved, record the blocker in Beads and report it
  plainly. Do not weaken security or call a workaround a completed fix.

## Writing standard

- **Use [Writing Clearly and Concisely](.agents/skills/writing-clearly-and-concisely/SKILL.md) for all prose.** Read the skill before writing, editing, or reviewing comments, documentation, UI copy, error messages, test descriptions, commit and PR text, reports, or agent messages.
- **One prose-style authority.** The writing skill takes precedence over style advice in other skills, guides, plans, and examples. Preserve product facts, terminology, accessibility, behavior, and approved decisions from those sources.
- **Preserve meaning and voice.** Match the product's audience. Use the skill's [confirmed samples](.agents/skills/writing-clearly-and-concisely/references/prince-voice.md) when drafting in Prince's voice; keep personal anecdotes and phone facts out of unrelated copy.
- **Explain what matters.** Say what something is and what it is used for. When data affects interpretation, explain its source and why it was chosen. Give test steps as an action and an expected result. State what changed, what was tested, and what remains unverified.
- **Highlight violations you encounter.** Flag unclear or wasteful prose even when writing is not the main task. Give its location, a short excerpt, the problem, and a proposed revision. Correct safe in-scope problems and report the change; discuss wider changes and record follow-ups through the project workflow.
- **Respect source ownership.** Preserve exact quotations and confirmed voice samples. Flag problems in quoted, third-party, or generated text, and correct the editable source where appropriate. Update generated output through its normal generation workflow.

## Reflection

When recurring friction, wasted tokens or effort, a meaningful correction, an unproductive approach, or a verified success suggests a reusable improvement, use [reflect](.agents/skills/reflect/SKILL.md). Bring a brief observation, its evidence, and a concrete proposal at a natural break. Discuss new lessons before preserving them or changing agent setup; existing user instructions still apply immediately. Keep independent work moving. Routine outcomes need no retrospective report. Use the project's existing tracker for agreed knowledge and follow-up work.

## UI Standards

Follow [`docs/page-template.md`](docs/page-template.md) for page work. Errors,
recovery guidance, copy feedback, and success notifications must follow
[`docs/error-and-feedback-standard.md`](docs/error-and-feedback-standard.md).

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Push the working branch, never `main`** - This is mandatory. Update it from
   `origin/main` without discarding unrelated work:
   ```bash
   git fetch origin
   git rebase origin/main
   bd sync
   git push -u origin HEAD
   git status  # MUST show "up to date with origin"
   ```
5. **Open or update the PR** - Target `main`. If none exists, run
   `gh pr create --base main`. Do not merge without user approval. Never bypass
   required checks.
6. **Clean up** - Remove only your temporary files. Preserve unrelated work and
   stashes; keep the PR branch until it is merged.
7. **Verify** - All task changes committed and pushed, signatures verified, and
   the PR open or merged with user approval.
8. **Hand off** - Give the PR link, test results, pending checks, and remaining work.

**CRITICAL RULES:**
- Sign every new commit and verify its signature before pushing.
- Push only the working branch. Never push directly to `main` or bypass its rules.
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
