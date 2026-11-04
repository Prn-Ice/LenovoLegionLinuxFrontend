# Error and Feedback Standard

Use these rules for errors, recovery instructions, copy buttons, and success
feedback. The privilege-setup dialog in
[`app_shell_components.dart`](../lib/core/widgets/app_shell_components.dart) is
the reference implementation.

Explain what failed, whether anything changed, and what to do next. Include the
cause when known.

## When to show feedback

| Situation | Presentation |
|---|---|
| An action failed or work is blocked | Modal error dialog |
| A destructive or privileged action needs approval | Confirmation dialog before dispatch |
| A routine action succeeded and the resulting state is visible | No notification; show the updated state |
| Text was copied | Change the originating button to `Copied` with a check icon |
| A save/export dialog completed | Let the platform dialog communicate the destination |
| A background value is unavailable | Explain it in place near the affected value |

Do not use snackbars, floating banners, toast overlays, or errors that shift the
page layout.

## What an error should say

Every error dialog should answer these questions in order:

1. **What failed?** Use a specific, human-readable title.
2. **What was the consequence?** State whether the requested change happened.
3. **Why did it fail?** Give the known cause in plain language.
4. **How can the user recover?** Give concrete, verified steps.
5. Show platform-specific steps only when needed.
6. **What did the system report?** Put selectable raw output under
   `Technical details`; never make it the primary message.

Do not use raw exceptions as titles, guess the cause, or claim success before
reading back the result from the authoritative state source.

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

Reuse the shared dialog. Add custom guidance only when a known failure needs
different recovery steps.

## Recovery for known errors

Use the privilege-setup error as the example for known failures:
`LegionBridgeErrorCode.privilegeSetup`, returned when the
`legion-control` D-Bus service or its authorization policy is not configured.

### Setup recovery

- A setup failure before dispatch means that command did not run. Do not claim
  that nothing changed if earlier steps in a multi-step action may have run.
- NixOS users must import the supplied module and enable both Polkit and
  `services.legionControl`.
- Other distributions must install the supplied systemd unit, D-Bus policy, and
  Polkit action.

Use this configuration for NixOS recovery:

```nix
security.polkit.enable = true;
services.legionControl = {
  enable = true;
  backendPackage = pkgs.lenovo-legion;
};
```

### Developer notes

- `legion-control` is a narrowly scoped root service, not a generic command
  runner.
- Polkit authorizes the frontend's unique D-Bus sender before writes are
  accepted.

When adding another known failure:

1. Identify the error in the service using an exit code or other reliable result.
2. State whether the attempted operation could have partially completed.
3. Check that the recovery steps work on the target platform.
4. Keep the raw error details available.
5. Add focused dialog and service-classification tests.

Pass `AppFailure` from the repository through Bloc state to the shared dialog.
Preserve `kind` and raw `details` when adding context. Choose recovery steps by
`kind`, not message text. Legacy string inputs remain unclassified. Test typed
propagation and recovery guidance without depending on the exact wording.

## Copyable Technical Content

Make configuration, commands, paths, and technical output selectable. Add a copy
button to code blocks.

- Use monospace only for code, commands, paths, and machine output.
- Preserve indentation and complete syntax so copied content can be used as-is.
- Use specific labels, such as "NixOS configuration".
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

Add success text only when the result is not visible or the user needs a next
step. Keep it beside the affected control, not in a floating notification.

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
