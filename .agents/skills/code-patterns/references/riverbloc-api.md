# Resolved API source map

This map concerns Riverbloc **3.0.0**, Riverpod/Flutter Riverpod **3.4.3**, and
Bloc **9.2.1**. Read the lockfile again after upgrades. Locate each package by
its `rootUri` in `.dart_tool/package_config.json`, not a hardcoded cache path.

| Contract | Resolved source to inspect |
| --- | --- |
| `BlocProvider<B, S>` exposes synchronous `S`; its factory returns `B` | `riverbloc/lib/src/bloc_provider.dart`: provider declaration, `_BlocProviderElement.create` |
| `.bloc` observes instance replacement, not emitted state | Same file: `bloc` getter |
| `overrideWith((ref) => replacement)` keeps the provider's element/lifecycle | `riverpod/lib/src/core/provider/functional_provider.dart`: `overrideWith` |
| The element subscribes to state, cancels its subscription, and closes its Bloc | `riverbloc/lib/src/bloc_provider.dart`: `create`, `runOnDispose` |
| Subscription cancellation and Bloc close completion are not awaited | Same `runOnDispose`; `riverpod/lib/src/core/provider_container.dart`: `runGuarded` |
| Default retention and opt-in auto-dispose | `riverbloc/lib/src/bloc_provider.dart`: constructor; `lib/src/builders.dart` |
| Family keys use argument equality and hashing | `riverbloc/lib/src/bloc_provider_family.dart`; `riverpod/lib/src/core/provider/provider.dart` |
| Emitted-state and selected-value notifications use equality | Riverbloc's `updateShouldNotify`; `riverpod/lib/src/core/modifiers/select.dart` |
| Events are concurrent by default; each `on<T>` applies its own transformer | `bloc/lib/src/bloc.dart`: `transformer`, `on` |
| `.when` stores mutable state outside a subscription | `riverbloc/lib/src/listenable_provider_whenable.dart`: `when` |

The published README/API comments still show `.notifier`, `maintainState`,
`overrideWithValue`, and `overrideWithProvider` for **BlocProvider**. Do not copy
those shapes. Read actual declarations and compile the intended usage.
Ordinary Riverpod `Provider` does support repository `overrideWithValue`; this is
not a ban on the valid repository overrides in our tests.

## Primary sources and local evidence

- [Published Riverbloc API](https://pub.dev/documentation/riverbloc/3.0.0/riverbloc/BlocProvider-class.html)
- [Riverbloc override declaration](https://pub.dev/documentation/riverbloc/3.0.0/riverbloc/BlocProvider/overrideWith.html)
- [Bloc concepts](https://bloclibrary.dev/bloc-concepts/)
- [Bloc concurrency](https://github.com/felangel/bloc/tree/master/packages/bloc_concurrency)
- [Riverpod disposal](https://riverpod.dev/docs/concepts2/auto_dispose)
- [Riverpod selection](https://riverpod.dev/docs/how_to/select)
- Local application contract: `test/core/riverbloc_contract_test.dart`

Upstream main and a sibling's lockfile are research inputs, not proof of the
installed version. Tests establish specific behavior, not every internal contract.
Keep executed checks and lookup failures in Beads; update this map when a new
release changes the API rather than collecting obsolete signatures here.
