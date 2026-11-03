# Minimal Riverbloc patterns

These are fragments using this app's Settings types, not a new architecture or
permission to split every screen. Consult [the usage guide](riverbloc.md) first.

## Constructor injection and one initial read

The production wiring in `lib/features/settings/providers/settings_provider.dart`
uses this shape:

```dart
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(
    controlClient: ref.watch(legionControlClientProvider),
  );
});

final settingsBlocProvider =
    BlocProvider.autoDispose<SettingsBloc, SettingsState>((ref) {
      final repository = ref.watch(settingsRepositoryProvider);
      return SettingsBloc(repository: repository)..add(const SettingsStarted());
    });
```

The constructor registers handlers; the factory starts the first read. Do not
also load from widget `build`. Keep real feature names and dependencies instead
of adding a forwarding provider just to resemble the example.

## Observe state; resolve commands at action time

Inside a Consumer's `build`, render from the state and read the current instance
inside the callback:

```dart
final state = ref.watch(settingsBlocProvider);

return TextButton(
  onPressed: state.themeMode == ThemeMode.system
      ? null
      : () => ref
          .read(settingsBlocProvider.bloc)
          .add(const ThemeModeChanged(ThemeMode.system)),
  child: const Text('Use system theme'),
);
```

Do not watch `.bloc` and render its `.state`, or capture a Bloc from `build` and
carry it across a confirmation/file-picker Future. After an awaited UI operation,
check `context.mounted` and resolve the current instance before acting.
The shell's title-bar callbacks in
`lib/features/navigation/view/navigation_shell.dart` show action-time reads.

## Tests own boundaries, providers own their Blocs

For production wiring tests, stub a repository's operations, then override that
ordinary repository provider:

```dart
final container = ProviderContainer.test(
  overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
);
final subscription = container.listen(settingsBlocProvider, (_, _) {});
final bloc = container.read(settingsBlocProvider.bloc);
```

Here `repository` is the test's configured fake/mock, not a real hardware client.
Hold the listener while exercising the auto-dispose provider. Complete a
controlled repository Future and wait for the relevant stream state, then pump
provider updates. Closing the listener and pumping lets you verify disposal;
wait for stream completion when proving cleanup, not just a changed `isClosed`.

For a narrow state-rendering test, a **BlocProvider** factory override has the
shape `settingsBlocProvider.overrideWith((ref) => replacementBloc)`. The provider
owns that replacement. Never return the same instance from several factories or
add a second teardown that closes it. A directly constructed Bloc outside a
provider is instead owned and closed by its test.

Use `test/core/riverbloc_contract_test.dart` as the complete controlled-load and
replacement example. Do not build tests around sleeps or a permissive package
constraint and call that lifecycle proof.
