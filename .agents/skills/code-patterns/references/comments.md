# Comments that explain the next step

Use `///` on a class or method for the caller's view. Use `//` beside a step
whose order matters. Choose the lines needed for the code in front of you:

```dart
/// [Caller] uses [entryPoint] to <goal>. It asks [helper] <specific question>.
/// If <condition>, <next action>. Otherwise, <who takes over>.

/// Returns <value> when <condition>. A <false/null/error> result means
/// <what the caller skips, stops, or tries next>.

// Do <step> before <later step>; otherwise <visible consequence>.
```

## Example: one bad entry or no usable list?

In `lib/core/services/power_profile_service.dart`, “Loads the snapshot” leaves
two questions: where did the profiles come from, and what does `null` mean?
Introduce `DBusPowerProfilesDaemonClient.loadSnapshot` from the caller's view:

```dart
/// Reads the active power profile and the available choices from the Linux
/// power profiles service. Returns null if the service can't be reached
/// or its reply can't be read. Without a snapshot, availableProfiles lists
/// the firmware choices instead.
```

For `parseProperties`, distinguish a missing field from a missing list:

```dart
/// Reads ActiveProfile and the list of Profiles from the service's reply.
/// Skips a profile with no text name and keeps the other named profiles.
/// Returns null if the active name is missing or no named profiles remain.
```

`_stringProperty` needs less. Its callers decide whether a field is required:

```dart
/// Returns the named field's text, or null if it's missing or isn't text.
```

## Example: the daemon accepted a setting. Why read it back?

“Verify state” is too vague beside the read in `PowerProfileService.setProfile`.
Name the two actors and say which one gets the final write:

```dart
// The Linux service may already report performance while the firmware is
// still in a vendor-only mode. Read the firmware after setting the service
// profile; if it still maps to a different profile, write the firmware setting.
```

Check the failure path before strengthening the claim: if the firmware read
returns `null`, this branch does **not** issue that corrective write. When you
encounter an older comment promising that a setting “always applies,” fix it
against the actual read and write conditions.
