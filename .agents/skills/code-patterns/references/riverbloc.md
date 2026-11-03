# Riverbloc: behavior in the Bloc, dependencies in the provider

Apply `AGENTS.md` and the parent skill. Use [examples](riverbloc-patterns.md)
for concrete shapes and the [API source map](riverbloc-api.md) when researching
the resolved implementation. These are conventions to clarify a feature, not
permission to rewrite every existing Bloc.

## Choose a behavior owner

- Prefer Cubit when named command methods make a small feature clearer. Use Bloc
  when events, tracing, or event concurrency add value. Keep sound existing Blocs.
- Inject repositories and stable inputs through constructors. Keep `Ref`, widget
  contexts, navigation, and other feature Blocs out of the behavior class.
- Keep state and events immutable. Use a cohesive value state or meaningful
  variants; do not add a second status enum around an adequate representation.
- Give each operation a visible happy path, awaited side effects, and explicit
  failure handling. Do not hide hardware actions in a generic callback dispatcher.

## Wire once and read the right thing

- Use ordinary co-located `BlocProvider<FeatureBloc, FeatureState>` declarations.
  The same provider supports Cubit; no separate `CubitProvider` or generation is
  needed. Keep repository/service providers only where they supply real inputs.
- `ref.watch(featureProvider)` returns synchronous **FeatureState**, not
  `AsyncValue<FeatureState>`. The feature models loading and errors itself.
- Render from that state. `.bloc` observes instance replacement, not state
  emissions; `ref.watch(featureProvider.bloc).state` misses state-driven rebuilds.
- In action callbacks, use `ref.read(featureProvider.bloc)` at action time, then
  call a Cubit method or add an event. Riverbloc 3 exposes `.bloc`, not `.notifier`.
- Start the initial read once per instance, normally from the provider factory
  after constructing the Bloc. Do not repeat it in widget `build` or lifecycle
  methods. Factories are synchronous: return the instance, not its loading Future.
- A factory's `ref.watch` declares a dependency whose changes recreate the Bloc.
  Watch only values that should restart the feature; do not use `read` to conceal
  a changing dependency. Never return one shared Bloc from multiple factories.

## Keep effects and prerequisites explicit

Declare `ref.listen` visibly in a Consumer's `build` for a real presentation
effect; Riverpod owns that subscription's lifetime. Put a substantial handler in
a focused feature-local function when it helps, but do not hide registration in
a hook-like helper, add a listener registry, or create a second DI tree.

Keep callbacks focused and guard meaningful transitions. Equality may suppress
identical states: repeated actions are not automatically distinct occurrences.
Model an occurrence only when the product needs it, not with a timestamp added
to every state. Use immutable `select` values when they prevent real unrelated
updates; a whole-state watch is fine for a cohesive page.

Do not duplicate error listeners already owned by `AppPageBody`, or turn a
routine success into a toast. The shared error/feedback standard still applies.
Moving an effect to another file does not move its work off the UI isolate.

Resolve asynchronous prerequisites at a clear boundary that distinguishes
loading, failure, and absence. Do not construct a fake Bloc with null repositories,
replace missing identities with empty strings, or throw normal loading as an
initialization error. Use an immutable family key or a deliberate scope override
only when the feature actually needs it. Family keys need stable equality and
hashing; parameterized instances need an intentional, bounded lifetime.

## Async boundaries and current instances

After a file picker, confirmation, or other awaited UI operation, check that the
view is still mounted before using its context/ref. Resolve the current Bloc
after the wait, rather than dispatching through an instance captured during
`build`. Recheck current capability/busy state where needed. This does not replace
backend authorization or atomic target validation for privileged operations.

Inside a Bloc, await handler work, including `emit.forEach` when used. Check
`emit.isDone` before emitting after work that may outlive a canceled handler.
Inside a Cubit, check `isClosed` where awaited work can outlive its owner.
Also guard post-await side effects: avoiding an emission is not enough if a
disposed feature can still start a poll timer or dispatch another command.

These guards prevent use after closure; they do not prevent an old read from
overwriting newer edits. Test those as separate promises.

## Choose concurrency, do not assume it

Bloc processes events concurrently by default. An `isApplying` guard can reject
some repeated writes; it does not automatically order polling, refresh, and
different write event types.

Prefer the supported transformers from
[`bloc_concurrency`](https://github.com/felangel/bloc/tree/master/packages/bloc_concurrency)
when they express the agreed behavior:

| Policy | Use and consequence |
| --- | --- |
| `sequential()` | Queue work. A slow operation delays later work. |
| `droppable()` | Ignore incoming events while that handler is busy. |
| `restartable()` | Replace earlier handlers for disposable reads. Canceling a handler need not cancel its I/O. |
| `concurrent()` | Allow overlap when ordering does not matter. |

Transformers apply to each `on<T>` registration. Two handlers each using
`sequential()` still have separate queues. If reads and writes must not overlap,
consider one shared `on<FeatureEvent>` registration that dispatches to focused
methods and awaits the write plus readback. Agree that trade-off first; do not
serialize every feature automatically. Never use cancellation as an assumed
rollback for a hardware write or authorization request.

`bloc_concurrency` is not currently a project dependency. These are options to
research and agree when a demonstrated race needs them, not instructions to add
the package or migrate handlers during unrelated work. Before introducing custom
revision counters or scheduling, show the race, explain the native alternative
and its cost, and obtain agreement for the added complexity.

## Ownership and disposal

- Riverbloc owns its created instance, including one returned by `overrideWith`.
  It calls `close` when the provider is disposed/recreated. Do not also close that
  instance in the widget or register another `ref.onDispose(bloc.close)`.
- A Bloc owns its timers and subscriptions and cancels them in `close`. A service
  provider may need its own `ref.onDispose` for a D-Bus client it creates; that is
  different from double-closing Riverbloc's instance.
- Default lifetime is retained; use `autoDispose` intentionally for route-bound
  work. A `read` alone does not keep an auto-dispose provider alive.
- Riverbloc does not await asynchronous close/cancel completion. Do not assume
  old cleanup finishes before a replacement starts. Test ordering if it matters.
- Preserve useful data and retryable input on refresh failure when required.
  First load, refresh, failed application, and confirmed hardware readback are
  different states; do not turn them into the same spinner or success message.

## Research, tests, and limitations

Recheck the lockfile and `.dart_tool/package_config.json`, then use Context7,
official API declarations, and resolved source. Published Riverbloc comments
include stale examples; a permissive Riverpod constraint is not compatibility
proof. Disclose failed lookups and name the source that settled a disagreement.

Run `test/core/riverbloc_contract_test.dart` after changing the Riverbloc/Riverpod
graph. It checks production provider initialization, state delivery, dependency
replacement, and disposal. Add focused [tests](testing.md) for changed ordering,
polling, confirmation, or disposal behavior; this contract test does not prove
every feature's async safety.

Avoid Riverbloc 3's `.when` extension: the resolved implementation captures mutable
filter state outside individual subscriptions. Prefer `select` for rendering
or a clear predicate inside a listener. This is a source-level concern, not a
reproduced application defect; it is unrelated to `AsyncValue.when`. Do not fork
Riverbloc without a minimal reproduction, compatibility tests, a small proposal,
and the owner's agreement.
