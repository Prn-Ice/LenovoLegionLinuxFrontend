# Flutter UI: reuse this app's Yaru patterns

Apply the parent skill during implementation and review. Start with the current
`docs/page-template.md` and `docs/error-and-feedback-standard.md`; they govern the
visual and feedback contract, together with the current shared components.
Do not import Ester's themes, dialogs, mobile dashboard, routes, or component API.

## Compose visible regions

Read the closest current feature and shared component before adding another
control. A build method should read like the screen, top to bottom. Extract a
meaningful region or repeated responsibility, not a widget per expression.
Feature boundaries watch state and dispatch commands; presentation components
receive values and callbacks. Simple presentation state may stay local.

Prefer a shared component, then a suitable native Yaru/Flutter control, before
inventing an interaction. Do not replace native keyboard, press, hover, focus,
or semantics behavior merely to achieve a small styling difference. Before
changing a shared default, find its callers and verify the affected surfaces.

Use `AppPageBody` for the page boundary, `SurfaceCard` for card surfaces, and
`ResponsiveCardGrid` for equal-card layouts. The navigation shell owns the page
name and title-bar refresh actions. Do not copy an older page's duplicate content
heading/refresh button into a new feature because it happens to exist.

## State must tell the hardware truth

Keep first load, unavailable support, empty results, stale-but-usable telemetry,
in-flight changes, and failed commands distinct where the feature needs them.
Support partial capabilities, not only fully populated mock snapshots.

Preserve missing measurements and their units/provenance through every layer.
Do not fabricate zero readings, plausible curves, history, or success. A
recommendation, chosen value, accepted command, and confirmed hardware state are
not interchangeable. Use backend readback where the UI promises actual state.

## Theme and available space

- Read semantic colors and typography from the existing Yaru/Flutter theme. Keep
  the page template's typography and packaged Ubuntu Mono helpers; no second
  font system, copied Ester tokens, or per-page typography scale.
- Resolve the authoritative interaction accent once per surface. Keep status
  meaning and GPU vendor identity separate from that accent. Check semantic
  foreground/background pairs in light and dark themes.
- Measure content constraints: the navigation rail reduces usable width. Reuse
  responsive components instead of adding repeated builders to rediscover width
  or passing viewport size through every component.
- Keep layouts usable in compact windows and with enlarged text and long labels.
  Scroll long bodies and keep actions reachable. Avoid fixed heights that hide
  failures or clip controls. Do not add tokens for nearly identical values.
- Use implicit transitions for ordinary value changes; own/dispose a controller
  only when sequencing genuinely needs one. Respect reduced motion and do not
  animate away an incomplete operation.

## Dialogs, authorization, and feedback

Privileged/destructive actions use `confirmPrivilegedAction` before dispatch and
the established `PrivilegedActionNotice` where appropriate. Dismissal must not
dispatch the action. After an awaited dialog/picker, check mounted state and
resolve the current Bloc; see the [Riverbloc guide](riverbloc.md).

Errors go through `AppPageBody`'s shared listener, or `showAppErrorDialog` for
view-owned failures. Do not add a second listener for the same error or introduce
snackbars, toasts, floating banners, or a page layout that shifts on failure.
Explain the action, consequence, classified cause, and concrete recovery; keep
raw details selectable and technical/configuration text copyable. Routine
success is visible in the updated state. Copy feedback belongs in its button.

UI capability checks and busy guards improve the flow; they are not the security
boundary. Keep typed D-Bus operations, Polkit, and backend allow-list/atomic
validation authoritative. Do not add a generic privileged-command fallback.

## Review the rendered result

Check whether a person can complete the action by keyboard and assistive
technology: useful labels, visible focus, traversal/return focus, independent
actions, non-color status cues, and an alternative to drag-only controls. Do not
hide an actionable subtree just to quiet announcements.

Review normal/narrow windows, relevant appearance variants, loading/error/empty
states, long names, missing values, text scaling, and reduced motion. Follow
[testing guidance](testing.md) for durable behavior assertions. Green widget tests
and shared class names do not establish visual fidelity or accessibility
conformance: state what was actually rendered/viewed and what remains unverified.
