# Documentation simplification proposal

Tracked in `lllf-z6w`.

This is the full proposed edit list. Nothing has been rewritten yet. Text not
listed stays unchanged, including commands, code examples, evidence tables,
source links, and required license text.

The Before column records the wording reviewed during the audit. Some rows
identify a whole paragraph or section rather than quoting it in full. Link
labels in the tables are plain text; existing destinations should be preserved
when applying the changes.

**Delete** means remove without replacement. **Move** means preserve the text but
put it in a more useful section.

## `README.md`

| Before | After |
|---|---|
| “A Flutter-based desktop frontend for [LenovoLegionLinux] — the open-source Linux kernel module and tooling for Lenovo Legion laptops.” | “A Linux desktop app for controlling Lenovo Legion laptops with [LenovoLegionLinux].” |
| “Power profile / platform profile switching” | “Power modes” |
| “Automation (run external programs on profile change)” | “Run programs when the power mode changes” |
| “Keyboard lighting (native Spectrum HID and OpenRGB)” | “Keyboard lighting through Spectrum HID or OpenRGB” |
| “The live application requires `legion_cli` in `PATH`, even when hardware features are unavailable. Use the hardware-free tests in [Contributing] for development without the backend.” | “Running the app requires `legion_cli` in `PATH`. You can [run tests without it].” |
| “Read operations use direct sysfs file reads or the read-only telemetry D-Bus service. Privileged writes use the typed `io.github.prnice.LegionControl1` system-bus API. That root service accepts only allow-listed operations, asks Polkit to authorize the frontend's D-Bus connection, and invokes fixed `legion_cli` or `systemctl` argument vectors without a shell. Dart never writes sysfs directly and never launches a privilege-elevation helper.” | “The app reads hardware data through sysfs and D-Bus. Changes go through the `legion-control` service, which checks permissions with Polkit.” |

Keep the existing architecture link and license section.

## `CONTRIBUTING.md`

| Before | After |
|---|---|
| “Thanks for helping improve Legion Linux Frontend. Open a GitHub issue to report a bug, request support, or discuss a change. Pull requests are welcome; link the related issue when there is one. A laptop, kernel module, CLI, and installed services are not needed for ordinary documentation, UI, parser, or test work.” | “Report bugs and discuss changes in GitHub issues. Link the related issue in your pull request. Most development and tests do not need Legion hardware or installed services.” |
| “Package names can vary by distribution release. Android SDK components are not needed for this Linux app.” | “Package names vary by distribution. You do not need the Android SDK.” |
| “For an optional Nix/direnv setup, set `LLLF_DEV_FLAKE` to a flake reference that provides Flutter and Linux build tools, then run `direnv allow`.” | “If you use Nix and direnv, set `LLLF_DEV_FLAKE` to a flake with Flutter and Linux build tools. Then run `direnv allow`.” |
| “Tests use fakes, mocks, and fixtures; they should not require a connected laptop, kernel module, `legion_cli`, system bus service, or privileged writes. Keep tests at the external boundary and do not make ordinary test runs depend on host hardware.” | “Use fake services and sample data so tests run without hardware, installed services, or administrator access.” |
| “The live application currently requires `legion_cli` in `PATH`: constructing `LegionCliService` fails if it cannot find the executable. Once the backend is installed, launch the application with:” | “Install `legion_cli` and make sure it is in `PATH`, then start the app:” |
| “Keep changes focused, preserve the sysfs/HID/D-Bus hardware boundaries, and add tests that reproduce behavior without a device.” | “Keep changes focused. Use the existing hardware services and add tests that run without a device.” |
| “In the pull request, describe the behavior changed, commands run and their results, and any hardware checks not performed.” | “In your pull request, say what changed, what you tested, and what you could not test.” |
| “Privileged writes go through typed `LegionControlClient` methods and the native allow-list. When adding a writable feature, update and test both the Dart mapping and the C++ validation. Do not launch privileged CLI writes from a repository, add an arbitrary command interface, or introduce a privilege-elevation fallback.” | “Use `LegionControlClient` for changes that need administrator access. Add and test the operation in both Dart and the C++ service. Do not run privileged commands directly or add an interface that accepts arbitrary commands.” |

## `docs/README.md`

Change link labels only; keep destinations.

| Before | After |
|---|---|
| “Contributing and implementation” | “Development” |
| “Contributing and checks” | “Contributing” |
| “Model support and fixture testing” | “Model support and testing” |
| “Dependency constraints” | “Dependencies” |
| “Platform surface adapters and integration limits” | “Desktop integrations” |
| “Hardware and operations” | “Hardware guides and investigations” |
| “Next-boot graphics requests and recovery” | “Change graphics mode at the next boot” |
| “M1CN hardware evidence” | “Legion Slim 7 16APH8 findings” |
| “Firmware power-defaults evidence” | “Power defaults investigation” |

## `docs/model-support.md`

| Before | After |
|---|---|
| “Track support per feature. Use diagnostics to identify whether a gap belongs to the kernel module/backend, frontend discovery, or keyboard HID support.” | “Some features may not work on every model. Run diagnostics to find out why.” |
| “Add or correct support” | “Report or fix a problem” |
| “Open a GitHub issue with the laptop model identifier and the feature or mismatch. Attach sanitized diagnostics when available; remove serial numbers, usernames, and other identifying data.” | “Open a GitHub issue with your laptop model and the problem. Attach diagnostics if available. Remove serial numbers, usernames, and other personal information.” |
| “Record BIOS, kernel, module, backend, and relevant device/protocol details. Say explicitly which features you tested and which remain unknown.” | “Include your BIOS, kernel, driver, and CLI versions. List what you tested and the results.” |
| “Reproduce discovery or parsing behavior with a small sanitized fixture. Add or update the relevant test so contributors without the laptop can verify it.” | “Add a test using a small sample of the diagnostic data, with personal information removed. The test should run without the laptop.” |
| “Change the narrow boundary that owns the behavior: driver/backend issue, frontend discovery, or tested keyboard mapping. Do not guess a fallback for unknown hardware.” | “Fix the problem in the driver, app, or keyboard mapping, as needed. Do not guess settings for unknown hardware.” |
| “Test on the affected machine when possible, then submit a pull request linking the issue, fixture, fix, and completed entry below. Clearly mark any checks not performed.” | “If possible, test the fix on the affected laptop. Link the issue and test results in your pull request, and fill in the template below. Note anything you could not test.” |
| “For keyboard lighting, include the USB vendor/product ID and evidence for the protocol, physical layout, and brightness calibration.” | “For keyboard lighting, include the USB vendor and product IDs, protocol, key layout, and brightness test results.” |
| “For sysfs-backed features, distinguish a readable value from a verified writable capability.” | “For sysfs features, report reading and writing separately.” |
| “Worked example: missing fan reading” | “Example: missing fan reading” |
| “Suppose an owner's diagnostics show a Legion fan provider that the frontend does not select.” | “Suppose diagnostics show a fan sensor that the app does not detect.” |
| “Change the selection rule in the service only if the evidence identifies the correct source. Preserve unknown results for unrecognized providers.” | “Update detection only when the diagnostics identify the correct sensor. Leave unknown sensors unsupported.” |
| “Ask the owner to verify the readout and attach that result to the issue. Record fan readings as tested; fan writes and other features remain untested unless separately checked.” | “Ask the owner to check the fan reading and post the result in the issue. Record only the features they tested.” |
| “Use `unknown` or `not tested` for fields you cannot verify.” | “Use `unknown` or `not tested` where needed.” |

Keep the detailed fixture example, constructor arguments, test command, and model
template.

## `docs/architecture/overview.md`

| Before | After |
|---|---|
| Opening paragraph describing sysfs, D-Bus, Polkit, fixed backend commands, elevation helpers, and automation. | “The app uses Flutter on Linux. It reads hardware data through sysfs and D-Bus. Hardware changes go through the C++ `legion-control` service, which checks permissions with Polkit and accepts only approved operations. Optional automation runs as the current user.” |
| “The keyboard lighting feature also has a native HID boundary: it communicates with supported keyboard devices through HID rather than the privileged control service.” | “Keyboard lighting communicates with supported keyboards through HID, not `legion-control`.” |
| “Code boundaries” | “Code layout” |
| “`lib/features/<feature>/` groups feature models, repositories, Bloc/Cubit behavior, providers, and views. Not every feature needs every directory.” | “`lib/features/<feature>/` contains each feature’s models, repositories, blocs, providers, and views.” |
| “`test/` contains hardware-free tests using fakes, mocks, and filesystem fixtures. Some tests cover widgets and rendered states as well.” | “`test/` contains tests that run without hardware, including widget tests.” |
| “Keep UI behavior in the existing feature patterns. Repositories isolate external I/O; Bloc/Cubit handles feature behavior; Riverpod supplies dependencies and lifetime.” | “Repositories access services. Bloc/Cubit manages feature behavior. Riverpod creates and disposes dependencies.” |
| “Following a request” | “How reads and changes work” |
| Paragraph beginning “For reads, a feature repository obtains current values…” | “Reads: service → repository → Bloc/Cubit state → UI.<br><br>Changes: UI → Bloc/Cubit → repository → `LegionControlClient` → native service. The service checks and applies the change. The feature then reloads its state or reports an error.” |
| “Readable state does not by itself prove that a write is supported.” | **Delete.** This belongs in model-testing guidance, where reading and writing are reported separately. |
| “Legacy callers use `LegionFrontendBridgeService.runPrivilegedCommand` for queuing and command history. Its CLI-shaped vocabulary is mapped by `LegionControlClient` to typed D-Bus methods; it is not an arbitrary command execution interface. New operations should use the typed client contract.” | “Older code uses `LegionFrontendBridgeService.runPrivilegedCommand` for queuing and command history. `LegionControlClient` maps these commands to approved D-Bus methods. Use `LegionControlClient` for new operations.” |
| “They save a request for a guarded boot service rather than switching graphics immediately.” | “They save the requested mode for the next boot.” |
| “The [sysfs/CLI access audit] records feature-specific access paths.” | “See the [sysfs/CLI access audit] for each feature’s read and write methods.” |

## `telemetry/README.md`

| Before | After |
|---|---|
| “`legion-telemetry-service` is a root-owned, read-only D-Bus service that turns the kernel's restricted RAPL energy counter into cached CPU package power. It never writes hardware state and does not use Polkit while sampling.” | “`legion-telemetry-service` reads the kernel’s restricted RAPL energy counter and provides CPU package power over D-Bus. It runs as root and does not change hardware settings.” |
| Paragraph beginning “A system package must install those files…” | “To install the service:<br>1. Install the bundled files under the matching `/usr` paths.<br>2. Run `systemd-sysusers`.<br>3. Add the desktop user to `legion-telemetry`.<br>4. Enable `legion-telemetry.service`.<br>5. Log out and back in.” |
| “This is the only administrative setup; normal reads never request authentication.” | “Reading telemetry does not require an authentication prompt.” |
| “The service exposes only `GetSnapshot` on `io.github.prnice.LegionTelemetry1`. Raw energy counters and arbitrary file access are not part of the API.” | “The D-Bus API provides one method: `io.github.prnice.LegionTelemetry1.GetSnapshot`.” |
| “Rebuild the system and start a new login session so the supplementary group is present. The module builds the helper from this source tree and uses its Nix store path directly.” | “Rebuild your system, then log out and back in to apply the group membership.” |

## `docs/dependencies.md`

| Before | After |
|---|---|
| “Stable dependencies” | “Dependencies” |
| “Use compatible stable packages and commit the resolved graph in `pubspec.lock`.” | “Use compatible stable packages and commit `pubspec.lock`.” |
| “Flutter and development environments” | “Flutter and build tools” |
| “Retained compatibility boundaries” | “Why some packages are held back” |
| “Keep `equatable: ^2.1.0` until a separately reviewed equality migration preserves those distinctions, including set/hash behavior. `test/core/event_equality_test.dart` guards the application contract.” | “Keep `equatable: ^2.1.0` until an upgrade preserves event equality and hashing. `test/core/event_equality_test.dart` checks this behavior.” |
| “Hive generation and the Flutter test graph” | “Hive code generation and test dependencies” |
| “They cannot share this application's test graph. A disposable Pub resolution with those versions reproduces the conflict; overriding analyzer or SDK test pins is not a fix.” | “These versions conflict with Flutter’s test dependencies. Do not override analyzer or Flutter’s pinned test packages.” |
| “Recheck when Flutter's test pins and a released generator/build graph accept the same newer analyzer. Leave transitive build/formatter packages to Pub rather than pinning or overriding them individually.” | “Recheck when Flutter’s test packages and the code generators support the same analyzer version. Let Pub choose indirect build and formatter dependencies.” |
| “Rechecked on 2026-11-04: the installed SDK and latest generator/build releases still have this boundary.” | “Checked on 2026-11-04: the conflict remains.” |
| “Keep the compatible graph above until the SDK test pins align…” | “Keep the versions above until Flutter supports the required test packages…” |
| Paragraph beginning “The app retains its Dart 3.11 source language floor…” | “The app uses Dart 3.11 syntax so the code generators can parse it. It still runs with the newer Dart bundled with Flutter. Raise the language version only when the generators support it, then regenerate the code. Do not hide parser errors or edit generated files.” |
| “Other transitive packages remain below their latest releases because their parents or Flutter constrain them…” | “Some indirect dependencies are also held back by Flutter or other packages…” |
| “Do not promote transitives to direct dependencies merely to make the output look current.” | “Do not add indirect dependencies to `pubspec.yaml` just to get newer versions.” |
| “Repeatable upgrade checks” | “Upgrade checklist” |
| “Read current release notes. Inspect the resolved implementation when documentation is stale. Probe major version conflicts in a disposable directory before editing the working graph. Update the manifest and lock together, preserving unrelated work.” | “Read the release notes. If the docs are outdated, check the installed package source. Try major upgrades in a temporary directory first. Update `pubspec.yaml` and `pubspec.lock` together.” |
| “`flutter pub upgrade --major-versions` is a useful probe, not permission to change equality, storage formats, or provider lifetime silently.” | “Review changes to equality, storage formats, and provider cleanup before accepting a major upgrade.” |
| “A passing resolver, test suite, or release build does not prove real Polkit/D-Bus authorization, device writes, file-picker portals, or visual behavior. Record those checks separately and state which were not performed.” | “Record hardware, authorization, file-picker, and visual checks separately from automated tests. Note which checks you did not run.” |

Keep all versions, conflict details, upgrade commands, and source links.

## `docs/page-template.md`

| Before | After |
|---|---|
| “Every new page … should follow the patterns below so the app stays consistent and the shared primitives keep paying off. Use the current shared components and theme values as the implementation reference.” | “Use the Dashboard as the reference for new pages. Reuse the shared components and theme values below.” |
| “A page is a `ConsumerStatefulWidget` (or `ConsumerWidget`) that composes blocs at the widget layer and renders into `AppPageBody`.” | “Use `ConsumerWidget` or `ConsumerStatefulWidget`. Watch the blocs in the page and render the content inside `AppPageBody`.” |
| “Blocs never listen to other blocs. If a page needs data from several blocs, `ref.watch` each one in the page and pass values down. (See the dashboard wiring power + sensors + devices together.)” | “Blocs must not listen to other blocs. Watch each bloc in the page and pass its values to child widgets.” |
| “No content title header…” and “Refresh lives in the title bar…” | “Put the page title and refresh action in the window title bar, not the page content. Configure them in `navigation_shell.dart`.” |
| “Errors use the shared modal dialog…” | “Pass errors to `AppPageBody`. Show routine success through the updated control. Follow the [error and feedback standard].” |
| “Always use `SurfaceCard` … never bare `YaruBorderContainer`, whose default fill is transparent (cards come out flat).” | “Use `SurfaceCard` for cards. It provides the standard background, border, and corner radius.” |
| “Pure value math (format, fraction, critical) is in … kept widget-free so it's unit-tested directly.” | “Keep formatting, fractions, and threshold calculations in `metric_format.dart`, where they can be tested without widgets.” |
| “Pass the surface's resolved accent into it; do not hardcode another chart or selector colour inside the card.” | “Pass the page or card accent to `TelemetryHistoryCard`. Use the same accent for its chart and selectors.” |
| Paragraph beginning “Keep the standard Material `SegmentedButton`…” | “Use `SegmentedButton` when the choices fit. Use `YaruPopupMenuButton` at narrower widths. Keep their selected colours consistent with the chart accent.” |
| “Every displayed measurement needs a documented unit and meaning. Preserve sign conventions and provenance in labels or supporting copy when ambiguity is possible.” | “Label measurements with their units. Explain the source or sign when it could be unclear.” |
| “Missing telemetry stays missing. Render `—` plus a concise explanation when useful; do not infer battery temperature, fabricate history, or substitute a related measurement without labeling it as such.” | “Show `—` for missing readings. Do not invent values or silently substitute another measurement.” |
| “Typography — the rule” | “Typography” |
| “Yaru's `TextTheme` is the scale for all text. Mono is the one exception. Do NOT build a parallel type scale.” | “Use Yaru’s `TextTheme` for text and the shared mono styles for telemetry numbers.” |
| “Sans → nearest Yaru `textTheme` slot” | “Text styles” |
| “Mono → `metric_text.dart` roles” | “Telemetry number styles” |
| “A test … locks this invariant.” | “Covered by `metric_text_test.dart`.” |
| “Neutral colours are theme-relative…” | “Use theme colours for neutral backgrounds, borders, and text so both light and dark themes work. Define semantic and vendor colours once per page or card.” |
| “Thread the resolved `Color accent` into cards. A deliberately semantic surface may own a stable accent instead … but it must still have one authoritative resolved colour.” | “Pass the power-mode accent to cards. A card may use a fixed colour when it has a clear meaning, such as green for Battery.” |
| “Keep one authoritative accent source per surface. Avoid a page-level hardcode combined with component-specific overrides that can disagree.” | **Delete.** Covered by the preceding accent instructions. |
| “Accent colours describe real state, not page identity. In particular, Custom violet belongs to an explicitly custom or dirty value…” | “Use violet for custom or unsaved values, not for an entire page of advanced settings.” |
| “Known hardware identity is the exception: show the detected manufacturer's mark rather than a decorative generic chip glyph…” | “For detected hardware, use the manufacturer’s logo in its vendor colour, with a neutral background and accessible label. Use a generic device icon when the manufacturer is unknown.” |
| “Vendor-aware presentation does not claim backend support for that vendor; capability remains a separate fact.” | **Delete.** |
| “Capability and state truth” | “Supported features and loading states” |
| “Discover backend capabilities before designing or enabling controls. Test the actual combinations the backend can return…” | “Enable controls only for supported features. Test partial support and no support, not just fully populated data.” |
| “Never invent hardware values or draw a plausible curve when the driver did not provide one. Preserve nullable states through the repository, bloc, and widget layers.” | “Keep missing values as `null` through the repository, bloc, and widgets.” |
| Paragraph beginning “Model first load separately from an empty result…” | “Show a loading state until the first read finishes or fails. Do not show zeros, `—`, or an empty process list before then.” |
| Paragraph beginning “Recommendation, explicit selection, successful application…” | “Keep recommendations, selections, completed commands, and confirmed hardware state separate. Show a setting as active only after reading it back.” |
| “Hide unsupported secondary controls. For the primary unavailable feature, show a compact explanation alongside any truthful telemetry that remains; do not leave a large disabled mock interface in place.” | “Hide unsupported secondary controls. If the page’s main feature is unavailable, explain why and show any readings that still work.” |
| “The shell owns the page name and refresh action…” | **Delete.** Already covered in the page skeleton. |
| “Toggles/buttons that change hardware go through a confirm + guard pattern…” | “Use `guard` to disable unsupported or busy controls and confirm hardware changes before applying them.” |
| “Keep authentication and save-work guidance compact and legible. It supports the task; it should not visually outweigh the action being explained.” | “Keep authentication and save-work guidance brief.” |
| “Reserve `colorScheme.error` for the destructive control and consequence, not the whole card. Destructive controls remain outlined unless there is a clear reason to make destruction the primary action.” | “Use `colorScheme.error` for destructive actions and warnings, not the whole card. Use outlined destructive buttons by default.” |
| “Confirmation copy names the exact targets when known … explains likely data loss or interruption, and uses a specific action label.” | “Name the affected processes or devices, explain any likely interruption or data loss, and use a specific action label.” |
| “UI preflight checks are not a security boundary. The privileged backend must atomically revalidate mutable targets immediately before acting; disabling a button or refreshing a process list only improves the frontend flow.” | “The privileged service must recheck targets immediately before acting, even if the UI already checked them.” |
| “A failed privileged action follows the [Error and Feedback Standard]: explain what failed … Keep raw tool output selectable under technical details.” | “Handle failures using the [error and feedback standard].” |
| “Section title bar: left-aligned … section-specific actions…” | **Delete.** Already covered in the page skeleton. |
| “Reconcile visual changes with established shell behaviour, proven backend capability, and direct review. Reuse app-wide accents and native controls.” | **Delete.** Repeats earlier rules. |
| Final “Hardware-specific data gaps” section. | **Delete the repeated rules.** Keep its model-support and M1CN links under “Related guides.” |

Keep the style tables, APIs, code samples, colour values, font-package warning,
and verification commands.

## `docs/error-and-feedback-standard.md`

| Before | After |
|---|---|
| “This document defines the required quality level for errors, recovery guidance, copy feedback, and routine success states.” | “Use these rules for errors, recovery instructions, copy buttons, and success feedback.” |
| “The goal is not merely to display an exception. A user who encounters an error must understand what failed, whether anything changed, why it failed when that is known, and what to do next.” | “Explain what failed, whether anything changed, and what to do next. Include the cause when known.” |
| “Interaction Policy” | “When to show feedback” |
| “Use interruption in proportion to the consequence:” | **Delete.** The table explains the policy. |
| “Do not use snackbars, floating banners, toast-like overlays, or page content that shifts when an error appears. They are easy to miss, compete with the task, and do not provide enough room for useful recovery guidance.” | “Do not use snackbars, floating banners, toast overlays, or errors that shift the page layout.” |
| “Error Message Hierarchy” | “What an error should say” |
| “What does the error mean? Explain the relevant system concept without assuming specialist knowledge.” | “Why did it fail? Give the known cause in plain language.” |
| “Does recovery differ by platform? Separate platform-specific guidance.” | “Show platform-specific steps only when needed.” |
| “Do not expose an exception string as the heading. Do not claim a cause that the service did not classify. Do not imply success without readback from the authoritative state source.” | “Do not use raw exceptions as titles, guess the cause, or claim success before reading back the result.” |
| “Do not build feature-specific generic error dialogs. Extend the shared dialog only when a classified failure has genuinely different recovery instructions.” | “Reuse the shared dialog. Add custom guidance only when a known failure needs different recovery steps.” |
| “Known Failure Guidance” | “Recovery for known errors” |
| “Known failures deserve structured, domain-specific content. The current reference is…” | “Use the privilege-setup error as the example for known failures…” |
| “The explanation must make these facts clear:” followed by internal service and authorization details mixed with recovery requirements. | Split into **Setup recovery** and **Developer notes**. Keep installation and partial-failure guidance under recovery. Move root-service scope and D-Bus sender authorization details to developer notes. |
| “The NixOS recovery block is canonical:” | “Use this configuration for NixOS recovery:” |
| “Classify it in the service layer from stable evidence such as an exit code or exact tool output.” | “Identify the error in the service using an exit code or other reliable result.” |
| “Verify every recovery instruction against the relevant platform behavior.” | “Check that the recovery steps work on the target platform.” |
| “Keep generic fallback details available for diagnostics.” | “Keep the raw error details available.” |
| Paragraph beginning “Carry the classified cause as an `AppFailure`…” | “Pass `AppFailure` from the repository through Bloc state to the shared dialog. Preserve `kind` and raw `details` when adding context. Choose recovery steps by `kind`, not message text. Test this without depending on the exact wording.” |
| “Configuration, commands, paths, and technical output must be selectable. A code block must also have a dedicated copy action because drag selection is a poor primary interaction for exact configuration.” | “Make configuration, commands, paths, and technical output selectable. Add a copy button to code blocks.” |
| “Label what the code is, not merely that it is code.” | “Use specific labels, such as ‘NixOS configuration’.” |
| “Success copy is justified only when the result is not otherwise observable or a meaningful next consequence must be communicated. In that case, prefer durable inline status near the affected control. A transient floating notification is still not appropriate.” | “Add success text only when the result is not visible or the user needs a next step. Put it beside the affected control, not in a floating notification.” |
| Final “Do and Do Not” section. | **Delete.** Its rules already appear above and in the verification checklist. |

Keep dialog behavior, accessibility requirements, partial-failure warnings, test
references, and the verification checklist.

## `docs/platform-surfaces.md`

| Before | After |
|---|---|
| “Platform surfaces” | “Desktop integrations” |
| “`lib/features/platform_surfaces/` contains presentation components and native adapters. They are not connected to app-lifetime feature producers or user preferences. They do not currently enable a tray, automatic OSD, or desktop notifications.” | “`lib/features/platform_surfaces/` contains code for a tray icon, on-screen display (OSD), and desktop notifications. These are not connected to the app yet.” |
| “Implemented boundary” | “Implemented” |
| “Typed confirmed-change values and a Flutter OSD widget” | “Change-event types and a Flutter OSD widget” |
| “Channel registered; Wayland unavailable; not Flutter visual parity” | “X11 only; appearance differs from the Flutter widget” |
| “No app registration, state menu, or actions wired” | “Not connected to app state or actions” |
| “No global listeners or persisted preference wired” | “Not connected to app events or saved preferences” |
| “Adapters present confirmed results; they do not authorize hardware changes. Any caller must preserve the existing confirmation, Polkit, backend validation, and readback flow.” | “Use these integrations to show confirmed changes. Send actions through the existing confirmation and hardware-control flow.” |
| “Initial loads, attempted writes, and unknown values must not be reported as successful changes.” | “Do not announce initial readings, pending changes, or unknown values as successes.” |
| “Hardware-free tests cover adapter contracts and lifecycle. They do not prove desktop focus, placement, menu appearance, accessibility, or compositor behavior.” | “Automated tests cover behavior and cleanup. Desktop appearance, focus, placement, and accessibility still need manual testing.” |

## `docs/platform-osd.md`

| Before | After |
|---|---|
| “Native OSD boundary” | “Native on-screen display” |
| Opening paragraph listing MethodChannel, plugin registration, no second engine, no hardware access, no startup popup, and window-close behavior. | “`NativeOsd` sends display events to a GTK popup through a MethodChannel. The popup is created when first needed. It is not connected to app events or preferences yet.” |
| “Capability and appearance” | “Supported desktops and appearance” |
| “It does not claim to follow the currently focused application's monitor.” | **Delete.** The preceding placement rule already says which monitor is used. |
| “Wayland: explicitly unavailable. GTK3 alone cannot guarantee global placement/stacking; no layer-shell dependency is installed. Do not advertise desktop OSD support there until a compositor-compatible host is implemented.” | “Wayland is not supported. The GTK3 implementation cannot reliably position the popup above other windows.” |
| “This is not a Flutter-rendered `PlatformOsd` window: its icon, accent, progress bar and exact Flutter surface are not reproduced.” | “The GTK popup uses the same labels as `PlatformOsd`, but not its icons, accent, or progress bar.” |
| “A separate engine just to reuse that widget would add substantial lifetime and theme synchronization complexity. Full visual integration remains open.” | **Delete.** Implementation rationale does not help callers use the adapter. |
| “The default lifetime is two seconds, bounded on both sides to 500–5000 ms.” | “The popup stays visible for two seconds by default. Durations are limited to 500–5000 ms.” |
| “Caller contract (not integrated)” | “Usage” |
| “One app-lifetime owner must dispose the adapter…” | “Create one adapter for the app and dispose it at shutdown…” |
| “Only a changed, completed authoritative snapshot is valid, not initial load, refresh, an attempted command or a failed write.” | “Show the popup only after a confirmed setting changes. Do not show it for initial readings, refreshes, pending changes, or failures.” |
| “The caller owns deduplication and the live preference/visibility sources.” | “The caller must prevent duplicate events and supply the current preference and window visibility.” |
| “An unavailable OSD is not a failed hardware operation and must not manufacture a success notification.” | “If the popup is unavailable, do not report the hardware operation as failed or show a replacement notification.” |
| “Verification limits” | “Testing” |
| Repeated final statements that app producers and preferences remain unconnected, desktop behavior is unverified, and visual parity and Wayland hosting are unimplemented. | **Delete repeated availability and appearance statements.** Keep one manual-testing list: “Still to test on X11: focus, click-through, replacement timing, shutdown, and accessibility.” |

Move channel ownership, timer cleanup, text bounds, and rendering details into a
**Technical details** section without dropping their requirements.

## `docs/platform-tray.md`

| Before | After |
|---|---|
| “Native tray adapter” | “Tray icon” |
| “This is an unwired foundation, not an enabled application feature.” | “The tray code is implemented but not connected to the app yet.” |
| Opening paragraph’s D-Bus object paths and transport details. | **Move** to a **D-Bus interface** section. |
| “Create `PlatformTray(DBusTrayTransport())` in the eventual application-lifetime owner, call `start()` once, publish snapshots with `updateMenu`, and await `dispose()` at teardown.” | “Create one `PlatformTray(DBusTrayTransport())` for the app. Call `start()` once, update it with `updateMenu`, and await `dispose()` at shutdown.” |
| “`TrayRegistration.registered` means only that the watcher accepted registration; it does not establish a host is present or an icon is visible. Never use it alone to enable minimize-to-tray.” | “Successful registration does not guarantee a visible tray icon. Do not enable minimize-to-tray based on registration alone.” |
| “A lost session-bus connection is not automatically reconnected: recreate the adapter after a transport failure.” | “After a session-bus connection failure, create a new adapter.” |
| “Registration failure without an owner change also needs an explicit retry strategy before integration.” | “The app must also retry registration failures when the watcher has not changed.” |
| “The owner must derive state and capabilities from confirmed feature snapshots, recheck busy/capability state on activation, and route commands through existing confirmation, Polkit and readback flows.” | “Build the menu from confirmed feature state. When an item is activated, recheck whether the action is supported and busy, then use the existing confirmation and control flow.” |
| “Callbacks must not expose privileged writes before hidden-window confirmation is designed.” | “Do not add privileged tray actions until confirmation works with the main window hidden.” |
| “The initial menu contains only a disabled unavailable status; no Open, Quit, hide, hardware action, or settings toggle is wired here.” | “The menu currently contains only a disabled ‘unavailable’ item. App and hardware actions are not connected.” |
| Final paragraph mixing incomplete protocol support, missing features, and unverified desktop behavior. | Split into **Not implemented** and **Not tested on a desktop** lists. Preserve each listed limitation. |

Keep menu-item fields, event rules, registration-owner handling, and protocol
references.

## `docs/platform-notifications.md`

| Before | After |
|---|---|
| “The native adapter is implemented, but is not wired globally. Construction is lazy: it does not contact the host. Tests inject a fake `DBusClient`; they never notify the developer's desktop or access hardware.” | “The notification code is implemented but not connected to the app yet. It connects to D-Bus only when needed. Tests use a fake client and do not send desktop notifications.” |
| “Caller contract” | “Usage” |
| “No appearance setting is wired to these inputs.” | “These inputs are not connected to app settings yet.” |
| “Until preferences finish loading, callers must pass false.” | “Keep notifications disabled until preferences have loaded.” |
| “Visibility must include both the current route and whether the window is visible; if unknown, conservatively pass true.” | “Treat the result as visible only when its page and the window are visible. If visibility is unknown, suppress the notification.” |
| “Keep feeding baseline observers even when notifications are disabled or the page is visible, so enabling notifications does not replay old changes.” | “Keep updating the observers while notifications are suppressed, so enabling them does not announce old changes.” |
| “Dispose the service once using `close()`; providers may register asynchronous service cleanup, not a second Bloc cleanup.” | “Call `close()` once at shutdown. A provider may close the service, but must not close the Bloc again.” |
| “Unavailable feedback does not fail the hardware operation and must not open another modal.” | “If notifications are unavailable, leave the hardware result unchanged and do not open an error dialog.” |
| “Confirmed sources and limitations” | “Supported events” |
| “The observers suppress initial/unknown values, loading/applying states and errors, retaining the last stable baseline during a write. They can report externally observed/polled changes too. They do not start the feature Blocs.” | “Observers ignore initial and unknown values, loading, pending changes, and errors. They keep the last confirmed value during a change and can detect changes made by other tools. They do not start the feature blocs.” |
| “Automation `lastRunSummary` combines completed, skipped and failed actions, including arbitrary external commands. It is not a safe blanket confirmed event source. A future producer must emit specific verified outcomes.” | “Do not use `lastRunSummary` as a success event: it mixes completed, skipped, and failed automation actions. Add events for specific confirmed results instead.” |
| “No app listener or persisted preference currently connects these adapters.” | **Delete.** Already stated at the beginning. |
| “Protocol and ownership” | “D-Bus details and cleanup” |
| “No absent server is auto-started.” | “The adapter does not start a notification server.” |
| “The client factory transfers ownership: return a fresh client, not a shared one.” | “The client factory must return a new client. The adapter owns and closes it.” |

Split the remaining protocol and disposal paragraphs into shorter paragraphs.
Preserve signatures, server-owner checks, queue behavior, and the dbus
pending-reply caveat.

## `docs/architecture/next-boot-graphics.md`

This file needs a structural change as well as sentence edits.

### Structure

| Before | After |
|---|---|
| Current instructions followed by a long series of implementation and incident updates. | Order sections as: **Current status → Enable → Request a mode → What happens at boot → Recovery → Test coverage → Historical results**. |
| Historical build paths, host revisions, boot IDs, timings, and incident records mixed into the main guide. | **Move** all dated result sections under **Historical results**, preserving their evidence. |
| Runtime sleep incidents mixed with graphics setup progress. | Group the two existing incident sections under **Sleep incidents** within Historical results. Keep their issue links and warnings. |

### Wording

| Before | After |
|---|---|
| “Tracked in `lllf-j9t.7`. This replaces repeated logout/TTY checks for the controlled Hybrid-to-iGPU-only workflow. It is opt-in and is not yet hardware-validated.” | “This optional feature changes between Hybrid and Hybrid iGPU-only at the next boot. Both directions have passed hardware tests on the recorded setup. Recovery after a failed transition, pending-request cancellation, and current sleep tests remain unverified. Tracked in `lllf-j9t.7`.” |
| “What changes” | “Enable next-boot graphics changes” |
| Paragraph beginning “Build and review the resulting generation before deployment…” | “Build and review the configuration before installing it. For initial setup, install it for the next boot rather than activating it in a running desktop. The reconciler does not restart during live configuration changes, but other changed services may restart.” |
| “No deployment is performed by the request command itself.” | **Delete.** The request behavior is explained beside the command. |
| “Do not use the host's legacy `no-nvidia` specialisation for this workflow. It removes PCI devices and uses activation-time firmware commands rather than this guarded contract.” | “Do not use the legacy `no-nvidia` specialisation. It changes firmware and removes PCI devices during activation.” |
| “Approve the normal Polkit prompt. The command saves a private, root-owned request and prints confirmation. It does not change graphics mode, log you out, or reboot. Save work and reboot yourself when ready. No new graphical page was added.” | “Approve the Polkit prompt to save the request. Graphics mode stays unchanged until you reboot. Save your work and reboot when ready.” |
| “Requests expire after 24 hours; an expired request or a backwards clock change blocks the attempt before any hardware command and requires a fresh request.” | “Requests expire after 24 hours. If the request expires or the clock moves backwards, submit a new request.” |
| “Other fixed operations” | “Other commands” |
| “Only Hybrid and Hybrid iGPU-only are accepted; Auto and Discrete are excluded.” | “Supported modes: Hybrid and Hybrid iGPU-only.” |
| “Cancellation removes a pending request, not an already-applied firmware policy. Requesting Hybrid queues a later-boot return to Hybrid.” | “Cancel removes a pending request. To return to Hybrid after a change, request Hybrid and reboot.” |
| “These ordering edges do not enable absent services.” | **Delete.** |
| “The backend performs its own last-moment client inspection; the earlier snapshot is not treated as permission to detach later.” | “The backend checks again for NVIDIA clients immediately before changing the mode.” |
| “These gates control known startup sources. They are not a kernel-enforced device-open lock against arbitrary system services or privileged programs. The guarded backend still has a small inspection-to-firmware-write race. Do not claim universal race freedom or add force-detach behavior to work around it.” | “Another privileged process could open the GPU between the final check and the firmware write. These checks reduce that risk but do not eliminate it. Do not force device removal.” |
| “Evidence and recovery” | “Status and recovery” |
| “The boot ID distinguishes a later boot from a live service restart.” | “The saved boot ID prevents a service restart from applying a request in the same boot.” |
| “`failed` or an interrupted `applying` request blocks later automatic attempts, including on another boot. It must not be cleared by cancelling, deleting the file, resetting the failed unit, or restarting the desktop. An explicit new request is required.” | “After a failure or interrupted attempt, submit a new request. Do not delete the state file or reset the service to bypass the block.” |
| “There is no automatic sudo fallback or generic root-command API.” | **Delete.** Keep the preceding administrative-recovery instruction. |
| “A failed attempt may already have changed firmware policy: do not assume that clearing an error would restore the old topology.” | “A failed attempt may still have changed the firmware setting. Clearing the error does not restore it.” |
| “Verification boundaries” | “Test coverage” |
| “Deployment and successful hardware boot must not be inferred from unit tests or a build. Record their actual results in the linked issue, with model, firmware, and deployed revision.” | “Record deployment and hardware results separately, including the model, firmware, and installed revision.” |
| “No generation was activated, no firmware was changed, and no reboot was requested while implementing and testing this flow.” | **Delete from the current summary.** The dated test results already distinguish builds from deployment. |
| “No new graphics request, deployment, sleep, or reboot was initiated while collecting this evidence.” | **Delete.** Retain the incident observations and unresolved questions. |
| “No further mode write or sleep was initiated by the agent during evidence capture.” | **Delete.** |
| “No new policy changes, intentional sleep test, diagnostic write, reboot, or graphics operation was initiated by the agent while collecting the evidence.” | **Delete.** |
| “Do not label it an automatic-idle loop without evidence, or dismiss the user's report because the sleep units returned success and current failed-unit lists are empty.” | “The cause of the second suspend is unknown. Successful sleep units do not explain the reported display problem.” |

Keep the detailed startup guards, recovery commands, timeouts, state handling,
and dated hardware evidence.

## `docs/architecture/m1cn-hardware-evidence.md`

| Before | After |
|---|---|
| “These observations apply to Lenovo `82Y4`, BIOS `M1CN48WW`, and the driver revisions recorded below. They are not a support claim for other firmware or models.” | “Tested hardware: Lenovo `82Y4`, BIOS `M1CN48WW`, with the driver revisions listed below.” |
| “Retained investigation reports are pinned in Git; temporary DSDT/MMIO files from those investigations are no longer available.” | “The linked reports are preserved in Git. Their temporary DSDT and MMIO files are no longer available.” |
| “The corrected module bound successfully and exposed `legion_hwmon`. That did not establish usable fan curves…” | “The corrected module exposed `legion_hwmon`, but its fan-curve readings were unusable…” |
| “Neither a bound module nor plausible-looking step indices prove writable curve support.” | **Delete.** The preceding findings already explain why the data is unusable. |
| “This proves one round trip, not safe ranges, other writes, persistence, or factory defaults.” | “Only this write and restore were tested. Safe ranges, other fields, persistence, and factory defaults remain unverified.” |
| “Support values `2` and `3` are capability codes, not choice bitmasks. Mode selection is distinct from settled PCI topology.” | “Support values `2` and `3` are capability codes, not bitmasks. Check the actual PCI devices after selecting a mode.” |
| “The retained hardware results establish:” | “Hardware test results:” |
| “The 262 build/deployment checks on November 3 did not establish equivalent hardware sleep coverage.” | “Sleep was not retested with systemd 262 on November 3.” |
| “These results do not establish external-display, X11, BIOS-recovery, or newer systemd sleep behavior.” | “Not tested: external displays, X11, BIOS recovery, and sleep with newer systemd versions.” |

## `docs/architecture/poweroff-stall-investigation.md`

| Before | After |
|---|---|
| “Poweroff diagnostics after live dGPU detach” | “Investigating a shutdown hang after disabling the dGPU” |
| Document begins with the original failure; successful retest appears later. | Add a short opening summary: “A shutdown hung after a live switch to iGPU-only. It did not recur after backend fixes. The original cause remains unknown.” |
| “The commands below describe the repository's diagnostic tooling, not a requirement to reproduce that machine's live detach.” | **Delete.** Keep the stronger “Do not repeat a live detach…” warning beside the diagnostic steps. |
| “What The Journal Proves” | “What the logs show” |
| “The affected boot did establish these boundaries:” | “The logs show:” |
| “Unresolved failure boundary” | “Where shutdown may have stopped” |
| “These phases” | “These possible stopping points” |
| “Hardened Retest Result” | “Retest after backend fixes” |
| “The original stall therefore did not reproduce after backend hardening and complete graphical/audio client quiescing.” | “The hang did not recur after the backend fixes and after closing graphics and audio clients.” |
| “Its precise root cause remains unknown, so a future recurrence needs fresh console or pstore evidence rather than attribution to the transient kworker.” | “The cause remains unknown. If it happens again, capture console or pstore logs; the brief kworker observation does not identify the cause.” |
| “Safe Evidence Capture” | “Capture diagnostic logs” |
| “A complete final snapshot moves suspicion to systemd-shutdown, kernel device shutdown, or ACPI S5.” | “If the final snapshot is complete, the hang happened later: in systemd-shutdown, device shutdown, or ACPI poweroff.” |
| “A failed arm restores the session automatically; a successful arm leaves it quiesced for poweroff.” | “If setup fails, the tool restores the session. If it succeeds, the session stays stopped for shutdown.” |
| “Stall Response” | “If shutdown hangs” |
| “For a later instrumented NixOS generation…” | “For deeper debugging on NixOS…” |

Keep all diagnostic commands, prerequisites, SysRq instructions, and warnings
about permanent firmware-backed logging.

## `docs/architecture/pipewire-logout-crash.md`

| Before | After |
|---|---|
| “A November 3, 2026 Plasma Wayland logout capture with PipeWire 1.6.9 strongly matches an upstream double-destruction bug in the X11-bell module.” | “PipeWire 1.6.9 crashed during Plasma Wayland logout on November 3, 2026. The logs and binary inspection strongly match a known X11-bell bug.” |
| “It is separate from graphics detach or hibernate results.” | **Delete.** |
| “DrKonqi's later `Connection refused` was a secondary forwarding failure after its logout socket closed.” | **Move** to the evidence section, after the PipeWire crash evidence. |
| “A compatible distro package containing that fix, or the exact backport, is the remediation identified by this evidence. The recorded investigation did not install or validate it locally.” | “Use a compatible distribution package containing the fix, or backport the commit. The fix has not been tested locally.” |
| “X11-bell can fail during Xwayland teardown inside a Wayland session; the stack does not imply an X11 desktop.” | “This X11-bell bug can also occur in a Wayland session when Xwayland closes.” |
| “Automatic PipeWire restart proves process recovery, not restored playback or capture.” | **Delete.** The validation section already requires audio checks. |
| “After a package fix, record the actual running executable/build and a normal logout/login time window.” | “After updating, record the running PipeWire version and the time of a normal logout and login.” |
| “A running service alone is not proof that logout succeeded without a crash.” | **Delete.** Already covered by checking for new crashes and restarts. |
| “The causal match is strong; core-register inspection and a fixed-version logout/audio test remain unverified.” | “Still to check: core registers and logout/audio behavior with the fix installed.” |

## `docs/power-defaults-evidence.md`

| Before | After |
|---|---|
| “Authoritative power defaults: firmware evidence” | “Power defaults investigation” |
| “Decision” | “Current status” |
| Opening decision paragraph. | “Firmware records contain power defaults for each feature and mode. Upstream LenovoLegionLinux exposes CPU PL1 and PL2 defaults, but a complete, verified preset is still missing for the app’s controls. Do not implement ‘Restore defaults’ using current readings, slider ranges, or the hard-coded display values.” |
| “This is not a claim that firmware defaults are unavailable on all models. It is a distinction between an implemented source, actual model/BIOS records, and a complete frontend restore contract. No model gains complete restore eligibility from this investigation alone.” | **Delete.** |
| “Subsequent staged backend implementation” | “Backend work in progress” |
| “The branch is pushed separately and is not merged or deployed.” | “The branch is pushed but not merged or installed.” |
| “Kernel compilation remains unverified because matching headers were unavailable; exact-model coverage and PPAB provenance still block a restore preset.” | “The kernel build has not been checked because matching headers were unavailable. A restore preset still needs complete model data and a verified PPAB default.” |
| “Evidence versions and scope” | “Sources and versions” |
| “It annotates displayed readings; it is not a backend defaults discovery API.” | “The map adds reference values to the display; it does not read defaults from the driver.” |
| “Those prior analyses are retained reports, not raw bytes rechecked today.” | “Only the earlier reports remain; the original files could not be rechecked.” |
| “What exists for each source/model class” | “Available defaults by source and model” |
| “Authoritative default availability” | “Verified defaults” |
| “This further rules out treating stable current settings as factory defaults.” | **Delete.** Already stated in Current status. |
| “No daemon, power-mode transition, or hardware command from those docs was run.” | **Delete.** |
| “Existing backend integration point” | “Where to add backend support” |
| “Neither name promises a complete multi-field reset.” | “Neither attribute provides a complete reset.” |
| “Independent upstream firmware contract” | “How LenovoLegionToolkit reads defaults” |
| “Its name alone is not evidence that all its values are defaults.” | “Do not treat all values returned by this method as defaults.” |
| “This is another firmware-interface lead, not a universal constant database. Neither Toolkit implementation establishes that these records exist on 82Y4/M1CN48WW.” | “Check whether these firmware records exist on `82Y4/M1CN48WW` before using them.” |
| “M1CN historical observations, without promoting them to a preset” | “Recorded M1CN values” |
| “Repeated observations verify read stability, not factory-reset semantics. The later controlled PL1 write/restore demonstrated a 54→53→54 W round trip, not an authoritative defaults query.” | “These captures show stable readings and a successful PL1 write and restore. They do not identify factory defaults.” |
| “PPAB: what is resolved and what remains bounded” | “PPAB: known facts and open questions” |
| “Resolved at the backend mapping/visibility level” | “Confirmed in the backend” |
| “Not resolved at the firmware level” | “Still unknown” |
| “These are possibilities to discriminate, not findings.” | **Delete.** The section is already labelled Still unknown. |
| “Neither 0 nor 20 W is approved as a restore default.” | “Do not use either 0 or 20 W as the PPAB restore default.” |
| “Its exclusion must be explicit in a future completeness decision.” | “A future restore design must explain how it handles missing PPAB data.” |
| “Existing visibility stays unchanged in this documentation-only investigation.” | **Delete.** |
| “Backend blocker and completion criteria” | “Required work” |
| “A getter with lazy initialization is not automatically side-effect-free; prefer static table/captured record analysis during read-only discovery.” | “Some getters initialize firmware state. Inspect static tables or saved records first to avoid changing hardware during discovery.” |
| “Do not let a partial map silently imply complete coverage. Missing Custom rows, unknown firmware, invalid/duplicate/truncated records and unresolved PPAB must fail closed.” | “Disable restore when required defaults are missing or invalid, the firmware is unknown, or PPAB remains unresolved.” |
| “Verify zero semantics from capability support and ranges rather than value truthiness.” | “Use support flags and ranges to determine whether zero is valid. Do not treat every zero as unsupported.” |
| “Only after complete authoritative coverage exists, implement the confirmed, AC/Custom-gated restore using the existing staged batch/rollback path and meaningful failure/recovery tests.” | “Once all required defaults are verified, add restore with confirmation, AC power and Custom-mode checks, the existing batch/rollback flow, and failure and recovery tests.” |
| “The existing `_m1cn48wwHardwareDefaults` display map also needs a provenance review under this blocker…” | “Also verify the sources for `_m1cn48wwHardwareDefaults`. Keep the ‘hardware defaults’ label only for entries backed by recoverable evidence. Handle any app behavior change separately.” |
| “This investigation does not authorize that edit.” | **Delete.** Covered by “Handle any app behavior change separately.” |
| Final “Evidence limits” section repeating missing firmware bytes, model records, complete coverage, and restore validation. | **Delete the repeated summary.** These gaps remain beside their relevant findings and required work. |

Keep source revisions, register and feature identifiers, tables, the PPAB
discrepancy, and linked evidence.

## `docs/architecture/sysfs-vs-cli-access-audit.md`

| Before | After |
|---|---|
| “sysfs vs legion_cli Access Audit” | “Hardware reads and writes” |
| “Access Strategy” | “Read and write methods” |
| “The frontend uses a consistent, principled split:” | **Delete.** |
| “This is correct and should be maintained.” | **Delete.** |
| “Read Surface” | “Reads” |
| “Write Surface” | “Writes” |
| “Repositories retain the CLI command vocabulary, but `LegionControlClient` maps it to typed D-Bus methods. The root service independently validates each request before constructing a fixed backend argument vector.” | “Repositories pass commands to `LegionControlClient`, which maps them to D-Bus methods. The root service validates each request and runs a fixed backend command.” |
| “Strategy A: Named subcommands” | “Named CLI commands” |
| “Strategy B: Generic `set-feature <FeatureName> <value>`” | “`set-feature` commands” |
| “Read-Only Features (no write path — by design)” | “Read-only features” |
| “The Power page shows an authoritative hardware-default baseline when one is known for the exact product and BIOS.” | “The Power page shows reference defaults only for an exact product and BIOS match.” |
| “The current model table is intentionally limited to Lenovo product `82Y4` with BIOS `M1CN48WW`, whose defaults were verified from firmware and repeated live captures.” | “The current table contains only Lenovo `82Y4` with BIOS `M1CN48WW`. See the [power-defaults investigation] for gaps in the supporting evidence.” |
| “Other systems show `Hardware default unavailable`; the frontend does not infer defaults from slider bounds or current values.” | “Other systems show `Hardware default unavailable`.” |
| “CLI Commands Available But Unused by Frontend” | “Unused CLI commands” |
| “What's working well” section, items praising the read/write split, dual write strategy, direct fan reads, and smaller privileged interface. | **Delete.** The access tables already document these choices. |
| “Items to note” | “Maintenance notes” |
| “`set-feature` `featureName` strings are magic constants…” | “Feature names passed to `set-feature` must exactly match the Python class names in `legion.py`. Link each name to its backend definition.” |
| “`monitor` command is a significant unused capability…” | “Consider `legion_cli monitor` for detecting changes made by other tools. It polls hardware state and returns JSON. Tracked in `okf.18`.” |
| “This is fine in practice … The CLI's … could reduce this to one process call if latency ever becomes an issue.” | **Delete.** Keep the measured “100 sysfs reads per load” observation without speculative optimization advice. |
| “Recommendation: Access Strategy Going Forward” | “Adding a feature” |
| “New writable features: Add a typed D-Bus method or extend an existing allow-list only after documenting ranges, payload limits, and backend argument construction; update both Dart and C++ tests.” | “For writes, document accepted values, payload limits, and backend arguments. Add the D-Bus method or allow-list entry, then update Dart and C++ tests.” |
| Final reactive-state recommendation repeating the `monitor` proposal. | **Delete.** Keep it once under Maintenance notes. |

The changed defaults wording avoids repeating a verification claim that the
newer investigation questions. This is a documentation correction, not a change
to the app.

## `assets/gpu_vendors/README.md`

| Before | After |
|---|---|
| “These marks identify detected hardware; their inclusion does not imply endorsement or broader backend support.” | “These marks identify detected hardware and do not imply endorsement.” |
| “Before replacing or recolouring a mark, verify its current Simple Icons source, licence metadata, and the vendor's current brand guidance.” | “Before replacing or recolouring a logo, check its source, licence, and vendor brand guidelines.” |
| “Keep an unknown-vendor fallback in the UI rather than guessing a manufacturer.” | **Delete.** Already covered in the page template. |

Keep retrieval dates, source links, and license and trademark conditions.

## `THIRD_PARTY_NOTICES.md`

| Before | After |
|---|---|
| “This pins the sources inspected for attribution; the original port's exact upstream revision was not recorded and has not been established.” | “This is the revision checked for attribution. The original port’s upstream revision is unknown.” |
| “These are modified Dart ports. Project history records…” | “The Dart ports were modified locally. Git history records…” |
| “The encoder extracts packet construction from the C++ HID driver…” | “The encoder ports packet construction from the C++ HID driver…” |
| “Reference screenshots, not declared application assets. No license or attribution notice was found alongside them; their redistribution provenance remains unresolved.” | “Reference screenshots, not app assets. No license or attribution notice was found, so permission to redistribute them is unverified.” |
| “The exact original OpenRGB port revision, screenshot permissions, individual vendor-mark metadata, and a complete inventory of dependency/runtime notices remain unverified.” | “Still unverified: the original OpenRGB revision, screenshot permissions, individual vendor-logo license details, and the complete dependency notice list.” |

Keep all credits, license names, copyright notices, source mappings, and
distribution requirements.

## What stays unchanged

- Required license text.
- Commands, configuration, APIs, protocol signatures, and numerical limits.
- Evidence tables, source revisions, and historical measurements.
- Concrete safety and recovery instructions.
- Project-owned and third-party agent skills; they are outside this
  documentation pass.

This is the complete proposed scope, not permission for additional unlisted
rewrites.
