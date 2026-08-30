# Error and Feedback Standard

This document defines the required quality level for errors, recovery guidance,
copy feedback, and routine success states. The privilege-setup dialog in
[`app_shell_components.dart`](../lib/core/widgets/app_shell_components.dart) is
the reference implementation.

The goal is not merely to display an exception. A user who encounters an error
must understand what failed, whether anything changed, why it failed when that
is known, and what to do next.

## Interaction Policy

Use interruption in proportion to the consequence:

| Situation | Presentation |
|---|---|
| An action failed or work is blocked | Modal error dialog |
| A destructive or privileged action needs approval | Confirmation dialog before dispatch |
| A routine action succeeded and the resulting state is visible | No notification; show the updated state |
| Text was copied | Change the originating button to `Copied` with a check icon |
| A save/export dialog completed | Let the platform dialog communicate the destination |
| A background value is unavailable | Explain it in place near the affected value |

Do not use snackbars, floating banners, toast-like overlays, or page content
that shifts when an error appears. They are easy to miss, compete with the task,
and do not provide enough room for useful recovery guidance.

## Error Message Hierarchy

Every error dialog should answer these questions in order:

1. **What failed?** Use a specific, human-readable title.
2. **What was the consequence?** State whether the requested change happened.
3. **What does the error mean?** Explain the relevant system concept without
   assuming specialist knowledge.
4. **How can the user recover?** Give concrete, verified steps.
5. **Does recovery differ by platform?** Separate platform-specific guidance.
6. **What did the system report?** Put selectable raw output under
   `Technical details`; never make it the primary message.

Do not expose an exception string as the heading. Do not claim a cause that the
service did not classify. Do not imply success without readback from the
authoritative state source.

## Dialog Behavior

Feature pages pass their current error into `AppPageBody`:

```dart
return AppPageBody(
  errorMessage: state.errorMessage,
  children: [
    // Page content remains stable behind the dialog.
  ],
);
```

`AppErrorDialogListener` opens one modal when a new non-empty error arrives. It
queues a different error if one is already visible rather than stacking
dialogs. The dialog requires an explicit close action and keeps the underlying
page layout unchanged.

Errors produced directly by a view, such as a failed file export, use the same
shared presentation:

```dart
await showAppErrorDialog(
  context,
  'Could not export telemetry: $error',
);
```

Do not build feature-specific generic error dialogs. Extend the shared dialog
only when a classified failure has genuinely different recovery instructions.

## Known Failure Guidance

Known failures deserve structured, domain-specific content. The current
reference is `LegionBridgeErrorCode.privilegeSetup`, detected when `pkexec`
reports that it must be setuid root.

The explanation must make these facts clear:

- `pkexec` is the Polkit helper that requests administrator authorization.
- It must start with effective root privileges before Polkit can authenticate.
- The command did not run, so the requested hardware or system setting did not
  change.
- NixOS supplies setuid programs through wrappers rather than setting the bit on
  immutable Nix store binaries.
- Most other distributions install `/usr/bin/pkexec` with the required
  root-owned setuid permissions through their Polkit package. They need no
  application-specific configuration. The same error there normally indicates
  damaged package permissions, a modified installation, or system hardening
  that an administrator must address.

The NixOS recovery block is canonical:

```nix
security.polkit = {
  enable = true;
  enablePkexecWrapper = true;
};
```

When adding another known failure:

1. Classify it in the service layer from stable evidence such as an exit code or
   exact tool output.
2. State whether the attempted operation could have partially completed.
3. Verify every recovery instruction against the relevant platform behavior.
4. Keep generic fallback details available for diagnostics.
5. Add focused dialog and service-classification tests.

Prefer carrying a structured error code to the presentation layer. If an
existing state currently carries only a string, keep the recognition token
stable and update the service and dialog tests together.

## Copyable Technical Content

Configuration, commands, paths, and technical output must be selectable. A code
block must also have a dedicated copy action because drag selection is a poor
primary interaction for exact configuration.

- Use monospace only for code, commands, paths, and machine output.
- Preserve indentation and complete syntax so copied content can be used as-is.
- Label what the code is, not merely that it is code.
- Change the copy button in place to `Copied` with a check icon.
- Do not open another dialog or floating notification to confirm a copy.
- Revert the copied state if the platform clipboard call fails.

The dialog content uses `SelectionArea`, while the NixOS configuration has its
own copy button. Generic errors provide `Copy details` for the complete error
text.

## Accessibility and Responsive Requirements

- Use a real modal route so focus, keyboard dismissal behavior, and screen
  reader traversal follow platform conventions.
- Provide an explicit title and close action. Color and the error icon are
  supporting cues, not the only indication of failure.
- Keep paragraphs left-aligned and scannable with descriptive section headings.
- Put long content in a scrollable dialog body; actions must remain reachable.
- Support compact desktop windows at least as small as `420 x 500` without
  overflow.
- Make technical text selectable and copy controls keyboard reachable.
- Use theme-relative surfaces and text colors so light and dark themes remain
  legible.

## Success and Notification Rules

Routine success should be visible in the state the user just changed. After a
write, reload the authoritative snapshot and render the resulting setting. Do
not add a success banner merely to repeat what the control already shows.

Success copy is justified only when the result is not otherwise observable or a
meaningful next consequence must be communicated. In that case, prefer durable
inline status near the affected control. A transient floating notification is
still not appropriate.

The BLoC state may retain historical `noticeMessage` fields while older flows
are migrated, but page views must not render them as global notifications.

## Verification Checklist

For every change to error or feedback behavior, verify:

- A new error opens exactly one dialog.
- The page does not re-open the same dialog on an unrelated rebuild.
- A different error is queued rather than stacked.
- The dialog remains until explicitly closed.
- The message names the failed action and whether state changed.
- Known failures provide accurate recovery steps and platform distinctions.
- Configuration and technical details are selectable and copyable.
- Copy feedback occurs inside the initiating control.
- The dialog has no overflow at normal and compact desktop sizes.
- No `SnackBar`, `ScaffoldMessenger`, floating banner, or toast was introduced.
- `flutter analyze` and the full widget test suite pass.

Reference tests live in
[`app_error_dialog_test.dart`](../test/core/widgets/app_error_dialog_test.dart).

## Do and Do Not

**Do:**

- Interrupt for blocked work and consequential failures.
- Explain the system concept in plain language before showing raw output.
- Separate general explanation, platform recovery, and technical details.
- Confirm when no command ran or no setting changed.
- Reuse the shared dialog and update its tests.

**Do not:**

- Show raw stderr alone.
- Place a multi-line error in a snackbar or banner.
- Show both a page banner and a dialog for the same failure.
- Use a second notification to confirm copying.
- Give NixOS instructions as if they apply to every distribution.
- Claim that a write succeeded until authoritative state confirms it.
