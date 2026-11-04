# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.


## Simple code and repeatable patterns

Read [the project code patterns](.agents/skills/code-patterns/SKILL.md) before
implementation, review, or test work. These adapt Ester's working agreement to
this Linux hardware frontend; Ester's product and deployment rules do not apply.

- Prefer plain names, direct control flow, focused functions, and a visible happy
  path. Optimize for the next reader, not the fewest lines.
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
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
