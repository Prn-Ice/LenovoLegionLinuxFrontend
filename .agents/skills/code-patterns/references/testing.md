# Tests that prove the changed promise

Apply the parent skill to production code and tests alike. Keep existing useful
tests; choose new checks for behavior, not quotas or a mandatory test for every
getter, framework guarantee, or generated field.

## Pick the right boundary

- Test parsing, units, nullable capabilities, validation, state transitions,
  failed writes/readback, retry, and meaningful equality contracts. A convenient
  fallback value must not turn missing hardware support into a false reading.
- Inject repository/service boundaries into a real Bloc. Use `bloc_test` and
  `mocktail` when they clarify setup and expected transitions, not as ceremony.
- Keep production provider wiring in lifecycle tests. Cover initialization,
  emitted-state notifications, dependency replacement, current-instance commands,
  and disposal as relevant. A manually constructed Bloc test cannot prove wiring.
- In widget journeys, normally keep real provider/Bloc wiring and replace I/O
  boundaries. Mocked state streams are useful for narrow rendering contracts,
  not proof that initialization, confirmation, or persistence actually works.
- Service/transport tests prove Dart-to-D-Bus mappings. C++ tests prove allow-list
  and parser behavior. Neither alone proves deployed D-Bus policy, real Polkit
  authorization, sender-disconnect revocation, or actual hardware readback.
- Unit/widget tests must not depend on the developer's hardware, system bus,
  installed `legion_cli`, or a privileged service. Use controlled local temporary
  fixtures where filesystem behavior matters.

## Control time, completion, and ownership

Give each test fresh mutable state. Prefer a `Completer` or an observable state
transition over arbitrary sleeps. For polling, use the test clock/fake time when
appropriate and control repository completion independently of timer ticks.

When async behavior changes, exercise disposal during the initial read, completion
after a dialog closes, a replaced provider, overlapping polls, repeated writes,
and refresh while the person edits. Test the particular ordering policy rather
than assuming a close guard also protects against stale results.

The provider owns its created/overridden Bloc. A direct Bloc unit test owns its
own instance. Close clients, timers, and subscriptions exactly once, and wait for
actual cleanup when the test's promise concerns completion. In particular,
canceling today's timer does not prove a pending initialization cannot start a
new one after disposal.

## UI contracts that last

Exercise first-load/loading, unavailable/partial support, error/retry, empty,
refresh with existing data, and ready states where they exist. Verify important
copy, callbacks, semantics, navigation, reachable actions, and no overflow.
Avoid private tree structure and exact padding/font/color assertions unless the
value is an agreed public contract, such as packaged telemetry-font behavior.

Use content constraints, not only full-screen width. This is a Linux desktop
app: include normal and narrow windows; error dialogs must support the established
420 × 500 compact case. Test intermediate layout branches, long hardware names,
missing measurements, and enlarged text. Do not import a mobile/web matrix from
Ester or claim a hidden button is usable because its widget exists.

For confirmation/error changes, use the actual launcher and check safe dismissal,
busy behavior, queued errors, and copy feedback against
`docs/error-and-feedback-standard.md`. For keyboard/accessibility changes, test
labels, focus, traversal, and reachable independent controls. Automated semantics
checks do not prove screen-reader usability or a formal accessibility standard.

## Run and report honestly

Use the commands in `CONTRIBUTING.md` and `docs/dependencies.md` inside the shared
Linux environment. `flutter test` is this Flutter app's native runner; use native
`dart test` only for a genuinely pure-Dart package if one is introduced. No new
wrapper or workspace tool is required.

Run focused tests first, then affected suites, full analysis/tests, generation
when models change, and relevant builds. Run
`test/core/riverbloc_contract_test.dart` for Riverbloc/Riverpod changes and native
service checks for C++ mapping/allow-list changes. A skipped integration check
must be reported as skipped, not as verified.

Record commands, resolved versions, results, and unverified surfaces in Beads.
Tests, a release build, rendered review, and a real hardware check are different
kinds of evidence. Never weaken an assertion, hand-edit generation, or add a
vacuous test to make an upgrade look green.
